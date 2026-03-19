import 'package:flutter/material.dart';
import '../api_service.dart';
import '../theme.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = "public";
  bool isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void handleRegister() async {
    final name = _nameController.text.trim();
    final mobile = _mobileController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter your name")));
      return;
    }

    if (mobile.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid mobile number")),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password must be at least 6 characters")),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      final res = await ApiService.register(
        name,
        mobile,
        password,
        _selectedRole,
      );
      if (!mounted) return;

      if (res.containsKey('user_id')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Registration successful")),
        );
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['detail'] ?? "Registration failed")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("CREATE ACCOUNT")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const Icon(
              Icons.person_add,
              size: 80,
              color: AppColors.primaryEmergency,
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Full Name",
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _mobileController,
              decoration: const InputDecoration(
                labelText: "Mobile Number",
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: "Password",
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "I AM A:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Public'),
                  selected: _selectedRole == 'public',
                  selectedColor: AppColors.primaryEmergency.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => _selectedRole = 'public'),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Driver'),
                  selected: _selectedRole == 'driver',
                  selectedColor: AppColors.primaryEmergency.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => _selectedRole = 'driver'),
                ),
              ],
            ),
            const SizedBox(height: 30),
            isLoading
                ? const CircularProgressIndicator(
                    color: AppColors.primaryEmergency,
                  )
                : ElevatedButton(
                    onPressed: handleRegister,
                    child: const Text("REGISTER NOW"),
                  ),
          ],
        ),
      ),
    );
  }
}
