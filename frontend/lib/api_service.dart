import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const int _alertCooldownSeconds = 30;

  static CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  static CollectionReference<Map<String, dynamic>> get _ambulance =>
      _db.collection('ambulance');
  static CollectionReference<Map<String, dynamic>> get _alerts =>
      _db.collection('alerts');

  static Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  static Future<Map<String, dynamic>> register(
    String name,
    String mobile,
    String password,
    String role,
  ) async {
    try {
      final cleanedName = name.trim();
      final cleanedMobile = mobile.trim();
      final cleanedPassword = password.trim();

      if (cleanedName.isEmpty) {
        return {'detail': 'Name is required'};
      }

      if (cleanedMobile.length < 10) {
        return {'detail': 'Valid mobile number is required'};
      }

      if (cleanedPassword.length < 6) {
        return {'detail': 'Password must be at least 6 characters'};
      }

      final existing = await _users
          .where('mobile', isEqualTo: cleanedMobile)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        return {'detail': 'Mobile number already registered'};
      }

      final now = FieldValue.serverTimestamp();
      final userRef = _users.doc();
      await userRef.set({
        'name': cleanedName,
        'mobile': cleanedMobile,
        'password': cleanedPassword,
        'role': role,
        'location': {'lat': 0.0, 'lng': 0.0},
        'is_active': false,
        'createdAt': now,
        'updatedAt': now,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userRef.id);
      await prefs.setString('token', userRef.id);
      await prefs.setString('name', cleanedName);
      await prefs.setString('role', role);

      if (role == 'driver') {
        await _ambulance.doc(userRef.id).set({
          'driverUserId': userRef.id,
          'driverName': cleanedName,
          'status': 'available',
          'is_active': false,
          'location': {'lat': 0.0, 'lng': 0.0},
          'createdAt': now,
          'updatedAt': now,
        });
      }

      return {'message': 'User registered successfully', 'user_id': userRef.id};
    } on FirebaseException catch (e) {
      debugPrint('Registration FirebaseException: code=${e.code}, message=${e.message}');
      return {'detail': 'Registration failed: ${e.message ?? e.code}'};
    } catch (e) {
      debugPrint('Registration exception: $e');
      return {'detail': 'Registration failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> login(
    String mobile,
    String password,
  ) async {
    try {
      final cleanedMobile = mobile.trim();
      final snapshot = await _users
          .where('mobile', isEqualTo: cleanedMobile)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) {
        return {'detail': 'User not found'};
      }

      final userDoc = snapshot.docs.first;
      final userData = userDoc.data();
      if ((userData['password'] ?? '') != password) {
        return {'detail': 'Invalid credentials'};
      }

      final data = {
        'access_token': userDoc.id,
        'user_id': userDoc.id,
        'role': userData['role'] ?? 'public',
        'name': userData['name'] ?? 'User',
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['access_token']);
      await prefs.setString('user_id', data['user_id']);
      await prefs.setString('role', data['role']);
      await prefs.setString('name', data['name']);

      // Save FCM token for notifications
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _users.doc(userDoc.id).update({'fcm_token': fcmToken});
      }

      return data;
    } catch (_) {
      return {'detail': 'Login failed'};
    }
  }

  static Future<bool> updateLocation(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final role = prefs.getString('role') ?? 'public';
    final emergencyActive = prefs.getBool('emergency_active') ?? false;
    final name = prefs.getString('name') ?? 'Driver';

    if (userId == null) {
      return false;
    }

    try {
      final now = FieldValue.serverTimestamp();
      await prefs.setDouble('last_lat', lat);
      await prefs.setDouble('last_lng', lon);

      await _users.doc(userId).set({
        'location': {'lat': lat, 'lng': lon},
        'updatedAt': now,
      }, SetOptions(merge: true));

      if (role == 'driver' && emergencyActive) {
        await _ambulance.doc('main').set({
          'driverUserId': userId,
          'driverName': name,
          'is_active': true,
          'status': 'busy',
          'location': {'lat': lat, 'lng': lon},
          'updatedAt': now,
        }, SetOptions(merge: true));
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> toggleEmergency(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final token = prefs.getString('token');
    final role = prefs.getString('role') ?? 'public';
    final name = prefs.getString('name') ?? 'Driver';
    final lastLat = prefs.getDouble('last_lat') ?? 0.0;
    final lastLng = prefs.getDouble('last_lng') ?? 0.0;

    if (userId == null || role != 'driver') {
      return false;
    }

    try {
      final now = FieldValue.serverTimestamp();
      await prefs.setBool('emergency_active', active);

      // Update Firestore ambulance doc
      await _ambulance.doc('main').set({
        'driverUserId': userId,
        'driverName': name,
        'is_active': active,
        'status': active ? 'busy' : 'available',
        'location': {'lat': lastLat, 'lng': lastLng},
        'updatedAt': now,
      }, SetOptions(merge: true));

      // Send to backend with location for instant FCM push
      if (active && lastLat != 0.0 && lastLng != 0.0) {
        try {
          final headers = <String, String>{
            'Content-Type': 'application/json',
          };
          if (token != null && token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
          }

          final response = await http.post(
            Uri.parse('$_backendUrl/emergency-status'),
            headers: headers,
            body: jsonEncode({
              'active': active,
              'latitude': lastLat,
              'longitude': lastLng,
            }),
          ).timeout(const Duration(seconds: 3));
          
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            debugPrint('Backend instant FCM: ${data['alerts_sent'] ?? 0} alerts sent');
          } else {
            debugPrint('Backend instant FCM failed: ${response.statusCode} ${response.body}');
          }
        } catch (e) {
          debugPrint('Backend FCM call error: $e');
        }
      }

      if (active) {
        await _alerts.add({
          'user_id': userId,
          'ambulanceId': userId,
          'message': 'Emergency mode activated',
          'severity': 'high',
          'status': 'active',
          'createdAt': now,
        });
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> processAmbulanceAlerts({bool forceImmediate = false}) async {
    try {
      final ambulanceDoc = await _ambulance.doc('main').get();
      if (!ambulanceDoc.exists) {
        return;
      }

      final ambulanceData = ambulanceDoc.data();
      if (ambulanceData == null) {
        return;
      }

      final isActive = ambulanceData['is_active'] == true;
      if (!isActive) {
        return;
      }

      final activeDriverUserId = ambulanceData['driverUserId'] as String?;

      final ambulanceLocation = ambulanceData['location'];
      if (ambulanceLocation is! Map<String, dynamic>) {
        return;
      }

      final ambulanceLat = (ambulanceLocation['lat'] as num?)?.toDouble();
      final ambulanceLng = (ambulanceLocation['lng'] as num?)?.toDouble();
      if (ambulanceLat == null || ambulanceLng == null) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final currentUserId = prefs.getString('user_id');

      final usersSnapshot = await _users.get();
      for (final userDoc in usersSnapshot.docs) {
        // Skip the driver themselves
        if (activeDriverUserId != null && userDoc.id == activeDriverUserId) {
          continue;
        }

        final userData = userDoc.data();
        final userLocation = userData['location'];
        if (userLocation is! Map<String, dynamic>) {
          continue;
        }

        final userLat = (userLocation['lat'] as num?)?.toDouble();
        final userLng = (userLocation['lng'] as num?)?.toDouble();
        if (userLat == null || userLng == null) {
          continue;
        }

        final distanceMeters = _haversineMeters(
          ambulanceLat,
          ambulanceLng,
          userLat,
          userLng,
        );

        if (distanceMeters <= 300) {
          final key = 'last_alert_ms_${userDoc.id}';
          final lastAlertMs = prefs.getInt(key);
          final cooldownMs = _alertCooldownSeconds * 1000;
            final inCooldown =
              !forceImmediate &&
              lastAlertMs != null &&
              (nowMs - lastAlertMs) < cooldownMs;
          if (inCooldown) {
            continue;
          }

          const message = '🚨 Ambulance coming - move left';
          debugPrint('[$distanceMeters m] $message for user ${userDoc.id}');

          // Write alert to Firestore (for in-app listener on public user's phone)
          await _alerts.add({
            'user_id': userDoc.id,
            'message': message,
            'timestamp': FieldValue.serverTimestamp(),
          });

          // Send FCM push notification via backend to the public user's phone
          final fcmToken = userData['fcm_token'] as String?;
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await _sendFcmViaBackend(fcmToken, '🚨 Emergency Alert', message);
          } else {
            debugPrint('Skipping FCM for ${userDoc.id}: missing fcm_token');
          }

          // If this user is currently logged in on THIS device, show local notification immediately
          if (currentUserId == userDoc.id) {
            await _showLocalEmergencyNotification(message);
          }

          await prefs.setInt(key, nowMs);
        }
      }
    } catch (e) {
      debugPrint('Ambulance alert cycle error: $e');
    }
  }

  /// Show a local notification for emergencies on the current device
  static Future<void> _showLocalEmergencyNotification(String message) async {
    try {
      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();
      
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'emergency_ambulance_channel',
        'Emergency Alerts',
        channelDescription: 'Ambulance proximity alerts',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );
      const NotificationDetails notificationDetails =
          NotificationDetails(android: androidDetails);
      
      await flutterLocalNotificationsPlugin.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '🚨 Emergency Alert',
        body: message,
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('Local notification error: $e');
    }
  }

  /// Send FCM push notification via backend API
  static Future<void> _sendFcmViaBackend(String token, String title, String body) async {
    try {
      final Uri url = Uri.parse('$_backendUrl/send-notification');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'title': title,
          'body': body,
        }),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        debugPrint('FCM notification sent successfully via backend');
      } else {
        debugPrint('FCM send failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('FCM backend call error: $e');
    }
  }

  static double _haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRadians(double degree) {
    return degree * (math.pi / 180.0);
  }

  // Email-based OTP authentication methods
  static String get _backendUrl {
    // Allow override with: flutter run --dart-define=BACKEND_URL=http://<host>:8000
    const fromEnv = String.fromEnvironment('BACKEND_URL', defaultValue: '');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }

    // Default to the host PC IP for real devices and emulators
    // PC IP found: 10.124.139.81
    if (!kIsWeb) {
      return 'http://10.124.139.81:8000';
    }

    return 'http://127.0.0.1:8000';
  }

  static Map<String, dynamic> _networkErrorMessage(Object e) {
    final message = e.toString();
    if (message.contains('Connection refused') ||
        message.contains('Failed host lookup') ||
        message.contains('SocketException')) {
      return {
        'detail':
            'Cannot connect to backend ($_backendUrl). Ensure your PC and phone are on the same Wi-Fi. Start backend with: uvicorn main:app --host 0.0.0.0 --port 8000 --reload',
      };
    }
    return {'detail': 'Error: $e'};
  }

  static Future<Map<String, dynamic>> registerInitiate(
    String email,
    String password,
    String name,
    String role,
  ) async {
    try {
      final Uri url = Uri.parse('$_backendUrl/register-initiate').replace(
        queryParameters: {
          'email': email.trim(),
          'password': password,
          'name': name,
          'role': role,
        },
      );
      final response = await http.post(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data as Map<String, dynamic>;
      }

      final error = jsonDecode(response.body);
      return error as Map<String, dynamic>;
    } catch (e) {
      return _networkErrorMessage(e);
    }
  }

  static Future<Map<String, dynamic>> verifyOTP(
    String pendingUserId,
    String otpCode,
  ) async {
    try {
      final Uri url = Uri.parse('$_backendUrl/verify-otp').replace(
        queryParameters: {
          'pending_user_id': pendingUserId,
          'otp_code': otpCode,
        },
      );
      final response = await http.post(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('access_token')) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', data['access_token']);
          await prefs.setString('user_id', data['user_id']);
          await prefs.setString('role', data['role']);
          await prefs.setString('name', data['name']);
        }
        return data;
      }

      final error = jsonDecode(response.body);
      return error as Map<String, dynamic>;
    } catch (e) {
      return _networkErrorMessage(e);
    }
  }

  static Future<Map<String, dynamic>> resendOTP(String pendingUserId) async {
    try {
      final Uri url = Uri.parse('$_backendUrl/resend-otp').replace(
        queryParameters: {
          'pending_user_id': pendingUserId,
        },
      );
      final response = await http.post(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data as Map<String, dynamic>;
      }

      final error = jsonDecode(response.body);
      return error as Map<String, dynamic>;
    } catch (e) {
      return _networkErrorMessage(e);
    }
  }

  static Future<Map<String, dynamic>> loginEmail(
    String email,
    String password,
  ) async {
    try {
      final Uri url = Uri.parse('$_backendUrl/login-email').replace(
        queryParameters: {
          'email': email.trim(),
          'password': password,
        },
      );
      final response = await http.post(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('access_token')) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', data['access_token']);
          await prefs.setString('user_id', data['user_id']);
          await prefs.setString('role', data['role']);
          await prefs.setString('name', data['name']);
        }
        return data;
      }

      final error = jsonDecode(response.body);
      return error as Map<String, dynamic>;
    } catch (e) {
      return _networkErrorMessage(e);
    }
  }

  static Future<Map<String, dynamic>> migrateToEmail(
    String oldMobile,
    String email,
    String newPassword,
  ) async {
    try {
      final Uri url = Uri.parse('$_backendUrl/migrate-to-email').replace(
        queryParameters: {
          'old_mobile': oldMobile,
          'email': email,
          'new_password': newPassword,
        },
      );
      final response = await http.post(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data as Map<String, dynamic>;
      } else {
        final error = jsonDecode(response.body);
        return error as Map<String, dynamic>;
      }
    } catch (e) {
      return {'detail': 'Error: $e'};
    }
  }

  static Future<void> logout() async {
    // Clear emergency mode and ambulance data before logging out
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final role = prefs.getString('role');

    if (userId != null && role == 'driver') {
      try {
        // Reset ambulance emergency status
        await _ambulance.doc('main').update({
          'is_active': false,
          'status': 'available',
        });
      } catch (_) {
        // Ignore errors during cleanup
      }
    }

    await _auth.signOut();
    await _clearLocalSession();
  }

  static Future<void> _clearLocalSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_id');
    await prefs.remove('role');
    await prefs.remove('name');
  }

  static Future<Map<String, dynamic>> createOrUpdateVerifiedUserProfile({
    required String uid,
    required String name,
    required String email,
    String role = 'public',
  }) async {
    try {
      final docRef = _users.doc(uid);
      final snapshot = await docRef.get();

      final existingData = snapshot.data() ?? <String, dynamic>{};
      final resolvedRole = (existingData['role'] as String?)?.trim().isNotEmpty == true
          ? (existingData['role'] as String)
          : role;
      final resolvedName = (existingData['name'] as String?)?.trim().isNotEmpty == true
          ? (existingData['name'] as String)
          : name;

      final fcmToken = await FirebaseMessaging.instance.getToken();
      final updatePayload = {
        'uid': uid,
        'name': resolvedName,
        'email': email,
        'role': resolvedRole,
        'location': {
          'lat': (existingData['location']?['lat'] as num?)?.toDouble() ?? 0.0,
          'lng': (existingData['location']?['lng'] as num?)?.toDouble() ?? 0.0,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!snapshot.exists) {
        updatePayload['createdAt'] = FieldValue.serverTimestamp();
      }
      if (fcmToken != null && fcmToken.isNotEmpty) {
        updatePayload['fcm_token'] = fcmToken;
      }

      await docRef.set(updatePayload, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', uid);
      await prefs.setString('user_id', uid);
      await prefs.setString('name', resolvedName);
      await prefs.setString('role', resolvedRole);

      return {
        'success': true,
        'name': resolvedName,
        'role': resolvedRole,
      };
    } catch (e) {
      return {'detail': 'Failed to sync profile: $e'};
    }
  }

  static Future<void> syncSessionFromCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null || !user.emailVerified) {
      return;
    }

    await createOrUpdateVerifiedUserProfile(
      uid: user.uid,
      name: (user.displayName?.trim().isNotEmpty == true)
          ? user.displayName!.trim()
          : 'User',
      email: user.email ?? '',
      role: 'public',
    );
  }

  static Future<Map<String, dynamic>> createUserProfile(
    String uid,
    String name,
    String email,
    String role,
  ) async {
    try {
      final now = FieldValue.serverTimestamp();
      await _users.doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email,
        'role': role,
        'location': {'lat': 0.0, 'lng': 0.0},
        'is_active': false,
        'createdAt': now,
        'updatedAt': now,
      });

      // If driver, create ambulance entry
      if (role == 'driver') {
        await _ambulance.doc(uid).set({
          'driverUserId': uid,
          'driverName': name,
          'status': 'available',
          'is_active': false,
          'location': {'lat': 0.0, 'lng': 0.0},
          'createdAt': now,
          'updatedAt': now,
        });
      }

      // Save to SharedPreferences for local access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', uid);
      await prefs.setString('name', name);
      await prefs.setString('role', role);

      return {'success': true, 'message': 'User profile created'};
    } catch (e) {
      debugPrint('Error creating user profile: $e');
      return {'detail': 'Failed to create user profile: $e'};
    }
  }
}

