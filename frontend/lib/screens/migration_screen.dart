import 'package:flutter/material.dart';
import '../theme.dart';

class MigrationScreen extends StatefulWidget {
  final String userToken;

  const MigrationScreen({super.key, required this.userToken});

  @override
  State<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends State<MigrationScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleMigration() async {
    // This would require knowing the old mobile number
    // For now, we'll show a message that migration is required
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Please log in again with your email to migrate"),
      ),
    );
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("UPDATE ACCOUNT")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const Icon(
              Icons.security_update_good,
              size: 80,
              color: AppColors.primaryRed,
            ),
            const SizedBox(height: 30),
            Text(
              "Update Your Account",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              "For better security, please update your account with an email address. This will enable email-based login and OTP verification.",
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: "Email Address",
                prefixIcon: Icon(Icons.email),
                hintText: "your.email@example.com",
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: "New Password",
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 30),
            isLoading
                ? const CircularProgressIndicator(
                    color: AppColors.primaryRed,
                  )
                : ElevatedButton(
                    onPressed: _handleMigration,
                    child: const Text("PROCEED WITH MIGRATION"),
                  ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
              },
              child: const Text("Go to Login"),
            ),
          ],
        ),
      ),
    );
  }
}
