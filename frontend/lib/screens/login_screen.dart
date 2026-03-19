import 'package:flutter/material.dart';
import '../api_service.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;

  void handleLogin() async {
    setState(() => isLoading = true);
    try {
      final res = await ApiService.login(_mobileController.text, _passwordController.text);
      if (!mounted) return;
      
      if (res.containsKey('access_token')) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['detail'] ?? "Login failed"))
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: Connection failed"))
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.medical_services, size: 100, color: AppColors.primaryEmergency),
              const SizedBox(height: 10),
              const Text("LIFE-TRACK", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.darkBlue)),
              const Text("Real-time Emergency Coordination", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 50),
              TextField(
                controller: _mobileController,
                decoration: const InputDecoration(labelText: "Mobile Number", prefixIcon: Icon(Icons.phone)),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock)),
                obscureText: true,
              ),
              const SizedBox(height: 30),
              isLoading 
                ? const CircularProgressIndicator(color: AppColors.primaryEmergency)
                : ElevatedButton(onPressed: handleLogin, child: const Text("LOGIN")),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/register'),
                child: const Text("Don't have an account? REGISTER", style: TextStyle(color: AppColors.accentMedium)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
