import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'services/voice_notification_service.dart';

class FcmService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _emergencyChannel =
      AndroidNotificationChannel(
    'emergency_ambulance_channel',
    'Emergency Alerts',
    description: 'Ambulance proximity alerts',
    importance: Importance.max,
  );
  static const String emergencyMessage = '🚨 Ambulance coming – move left';
  static bool _initialized = false;
  static StreamSubscription<RemoteMessage>? _onMessageSubscription;
  static StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;
  static StreamSubscription<String>? _onTokenRefreshSubscription;

  static Future<String?> initialize() async {
    if (_initialized) {
      return _firebaseMessaging.getToken();
    }

    // Initialize VoiceNotificationService for TTS
    await VoiceNotificationService().initialize();

    // 1. Request permission
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted permission');
    } else {
      debugPrint('User declined or has not accepted permission');
      return null;
    }

    // 2. Local Notifications Setup (for foreground messages)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _localNotificationsPlugin.initialize(settings: initializationSettings);
    await _localNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_emergencyChannel);
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. Get FCM Token & Save to Firestore
    String? token = await _firebaseMessaging.getToken();
    if (token != null) {
      debugPrint("FCM Token: $token");
      await _updateTokenInFirestore(token);
    }

    // Refresh token listener
    _onTokenRefreshSubscription =
      _firebaseMessaging.onTokenRefresh.listen(_updateTokenInFirestore);

    // 4. Foreground Message Listener
    _onMessageSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        _showLocalNotification(
          message.notification!.title ?? 'Alert',
          message.notification!.body ?? '',
        );
      }
    });

    _onMessageOpenedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final title = message.notification?.title ?? 'Emergency Alert';
      final body = message.notification?.body ?? emergencyMessage;
      _showLocalNotification(title, body);
    });

    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      final title = initialMessage.notification?.title ?? 'Emergency Alert';
      final body = initialMessage.notification?.body ?? emergencyMessage;
      await _showLocalNotification(title, body);
    }
    
    _initialized = true;
    return token;
  }

  static Future<void> dispose() async {
    await _onMessageSubscription?.cancel();
    await _onMessageOpenedAppSubscription?.cancel();
    await _onTokenRefreshSubscription?.cancel();
    _onMessageSubscription = null;
    _onMessageOpenedAppSubscription = null;
    _onTokenRefreshSubscription = null;
    _initialized = false;
  }

  static Future<void> _updateTokenInFirestore(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId != null && userId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({'fcm_token': token, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true))
          .catchError((e) => debugPrint("Failed to update token: $e"));
    }
  }

  static Future<void> _showLocalNotification(String title, String body) async {
    // Check if user has enabled voice notifications
    final prefs = await SharedPreferences.getInstance();
    final voiceNotificationsEnabled =
        prefs.getBool('voice_notifications_enabled') ?? true; // Default to enabled

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'emergency_ambulance_channel',
      'Emergency Alerts',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _localNotificationsPlugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
    );

    // Play voice notification if enabled
    if (voiceNotificationsEnabled) {
      final voiceMessage = '$title. $body';
      await VoiceNotificationService().speakAlert(voiceMessage);
    }
  }

  static Future<void> showEmergencyLocalNotification({
    String message = emergencyMessage,
  }) async {
    await _showLocalNotification('Emergency Alert', message);
  }
}

// Global background handler required by Firebase Messaging
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}
