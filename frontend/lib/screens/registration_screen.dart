import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  String _selectedRole = 'public'; // Default role
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return emailRegex.hasMatch(email);
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final res = await AuthService.registerWithEmail(
        name: _nameController.text.trim(),
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
                Text('Verification link sent to your email'),
              ],
            ),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pushNamed(
          context,
          '/email-verification',
          arguments: {
            'email': _emailController.text.trim(),
            'name': _nameController.text.trim(),
            'role': _selectedRole, // Pass selected role
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['error'] ?? 'Registration failed'),
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
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
                'Join the System',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Register for the Digital Traffic Bubble.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
              const SizedBox(height: 30),

              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role Selection
                    const Text(
                      'I AM A:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryBlue,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildRoleCard('public', 'Public', Icons.people_outline_rounded)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildRoleCard('driver', 'Driver', Icons.medical_services_outlined)),
                      ],
                    ),
                    const SizedBox(height: 30),

                    TextFormField(
                      controller: _nameController,
                      keyboardType: TextInputType.name,
                      validator: (v) => (v != null && v.trim().isNotEmpty) ? null : 'Enter your name',
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => _isValidEmail(v ?? '') ? null : 'Enter valid email',
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      validator: (v) => (v != null && v.length >= 6) ? null : 'Password must be 6+ chars',
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
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _handleRegister,
                            child: const Text('REGISTER'),
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account? '),
                  GestureDetector(
                    onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                    child: const Text(
                      'LOG IN',
                      style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(String role, String label, IconData icon) {
    bool isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryRed : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryRed : AppColors.borderLight,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryRed.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppColors.textSecondary,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
