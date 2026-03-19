import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // Delay for visual effect
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final token = prefs.getString('token');

    if (!mounted) return;

    // If user has token and userId, go to dashboard
    if (userId != null && token != null) {
      Navigator.of(context).pushReplacementNamed('/dashboard');
    } else {
      // Otherwise go to login
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.medical_services,
              size: 80,
              color: Color(0xFFE63946),
            ),
            SizedBox(height: 20),
            Text(
              'LIFE-TRACK',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1D3557),
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Real-time Emergency Coordination',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE63946)),
            ),
          ],
        ),
      ),
    );
  }
}
