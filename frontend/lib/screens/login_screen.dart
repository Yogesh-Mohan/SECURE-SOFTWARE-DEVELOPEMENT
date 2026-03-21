import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _requestCorePermissions() async {
    await Permission.notification.request();
    await Geolocator.requestPermission();
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return emailRegex.hasMatch(email);
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final res = await AuthService.loginWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Login successful!'),
              ],
            ),
            backgroundColor: AppColors.success,
          ),
        );
        await _requestCorePermissions();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else if (res['needsVerification'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['error'] ?? 'Email not verified'),
            backgroundColor: AppColors.primaryRed,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'VERIFY',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/email-verification',
                  arguments: {
                    'email': _emailController.text.trim(),
                    'name': '',
                  },
                );
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['error'] ?? 'Login failed'),
            backgroundColor: AppColors.primaryRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 30),
              // App Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryRed.withValues(alpha: 0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Image.asset('assets/app_logo.png'),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Digital Traffic',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Log in to the Bubble System dashboard.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
              const SizedBox(height: 50),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => _isValidEmail(v ?? '') ? null : 'Enter valid email',
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      validator: (v) => (v != null && v.isNotEmpty) ? null : 'Enter valid password',
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 44),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: _handleLogin,
                            child: const Text('LOGIN'),
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Don\'t have an account? '),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/register'),
                    child: const Text(
                      'Register Now',
                      style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
