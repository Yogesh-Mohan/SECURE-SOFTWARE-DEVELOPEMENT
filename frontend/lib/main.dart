import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'background_service.dart'; // TODO: Re-enable after fixing foreground service notification
import 'fcm_service.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

Future<void> _verifyFirebaseConnection() async {
  try {
    await FirebaseFirestore.instance.collection('users').limit(1).get();
    debugPrint('Firebase connection successful');
  } catch (e) {
    debugPrint('Firebase connection failed: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await _verifyFirebaseConnection();

  // Setup Firebase Messaging Background Handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Request notification permissions
  await Permission.notification.request();

  // TODO: Initialize background service when Android foreground service notification is properly configured
  // For now, disabled to prevent app crash on startup
  // await initializeBackgroundService();

  runApp(const EmergencyTrackingApp());
}

class EmergencyTrackingApp extends StatelessWidget {
  const EmergencyTrackingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emergency Track',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegistrationScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}
