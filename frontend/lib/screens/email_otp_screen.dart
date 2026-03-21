import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String name;
  final String role; // Added role parameter

  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.name,
    this.role = 'public', // Default to public
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isChecking = false;
  bool _isResending = false;
  bool _isVerified = false;
  int _resendCooldown = 0;
  int _resendCount = 0;
  Timer? _cooldownTimer;
  Timer? _autoCheckTimer;

  @override
  void initState() {
    super.initState();
    // Auto-check every 5 seconds
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkVerification(silent: true));
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _checkVerification({bool silent = false}) async {
    if (_isVerified) return;
    if (!silent) setState(() => _isChecking = true);

    try {
      final verified = await AuthService.checkEmailVerified();
      if (!mounted) return;

      if (verified) {
        setState(() => _isVerified = true);
        _autoCheckTimer?.cancel();

        final user = AuthService.currentUser;
        if (user != null) {
          await AuthService.saveUserToFirestore(
            uid: user.uid,
            name: widget.name.isNotEmpty ? widget.name : (user.displayName ?? 'User'),
            email: user.email ?? widget.email,
            role: widget.role, // Pass the selected role
          );
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified! Navigating to dashboard...'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (_) => false);
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification link not yet clicked. Please check your inbox.'),
            backgroundColor: AppColors.primaryRed,
          ),
        );
      }
    } finally {
      if (mounted && !silent) setState(() => _isChecking = false);
    }
  }

  Future<void> _handleResend() async {
    if (_resendCount >= 5 || _resendCooldown > 0) return;

    setState(() => _isResending = true);
    try {
      final res = await AuthService.resendVerificationEmail();
      if (!mounted) return;

      if (res['success'] == true) {
        setState(() => _resendCount++);
        _startCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email resent!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to resend. Please try later.'),
            backgroundColor: AppColors.primaryRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('EMAIL VERIFICATION'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () {
            AuthService.logout();
            Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primaryRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryRed.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  size: 50,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Verify Your Email',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                  children: [
                    const TextSpan(text: 'We sent a verification link to\n'),
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 44),
              
              // Instructional Steps
              _buildStep(1, 'Open your email application'),
              const SizedBox(height: 16),
              _buildStep(2, 'Tap the verification link we sent'),
              const SizedBox(height: 16),
              _buildStep(3, 'Wait for this screen to redirect automatically'),
              const SizedBox(height: 50),

              _isChecking
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: () => _checkVerification(),
                      child: const Text('CHECK VERIFICATION NOW'),
                    ),
              const SizedBox(height: 24),
              _isResending
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: (_resendCount < 5 && _resendCooldown == 0) ? _handleResend : null,
                      child: Text(
                        _resendCooldown > 0
                            ? 'Resend email in ${_resendCooldown}s'
                            : 'Resend Verification Email (${5 - _resendCount} left)',
                        style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold),
                      ),
                    ),
              const SizedBox(height: 40),
              Text(
                'Auto-checking every 5 seconds...',
                style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(int num, String text) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(color: AppColors.primaryBlue, shape: BoxShape.circle),
          child: Center(
            child: Text(
              '$num',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
