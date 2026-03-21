import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkAuthStatus();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthStatus() async {
    // Visual delay for branding
    await Future.delayed(const Duration(milliseconds: 2000));

    if (!mounted) return;

    final isLoggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;

    if (isLoggedIn) {
      // Sync profile on auto-login
      final user = AuthService.currentUser;
      if (user != null) {
        await AuthService.saveUserToFirestore(
          uid: user.uid,
          name: user.displayName ?? 'User',
          email: user.email ?? '',
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/dashboard');
    } else {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryRed.withValues(alpha: 0.2),
                      blurRadius: 40,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Image.asset(
                    'assets/app_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 50),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  AppColors.primaryRed,
                  AppColors.primaryBlue,
                ],
              ).createShader(bounds),
              child: const Text(
                'DIGITAL TRAFFIC\nBUBBLE SYSTEM',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Secure Emergency Network',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 60),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}
