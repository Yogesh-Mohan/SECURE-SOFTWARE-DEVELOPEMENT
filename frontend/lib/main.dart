import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'fcm_service.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/email_otp_screen.dart'; // EmailVerificationScreen
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

  runApp(const EmergencyTrackingApp());
}

class EmergencyTrackingApp extends StatelessWidget {
  const EmergencyTrackingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DIGITAL TRAFFIC BUBBLE SYSTEM',
      debugShowCheckedModeBanner: false,
      theme: medicalTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegistrationScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/email-verification') {
          final args = (settings.arguments as Map<String, dynamic>?) ?? {};
          return MaterialPageRoute(
            builder: (context) => EmailVerificationScreen(
              email: (args['email'] ?? '').toString(),
              name: (args['name'] ?? '').toString(),
              role: (args['role'] ?? 'public').toString(),
            ),
          );
        }
        return null;
      },
    );
  }
}
