import 'package:flutter/material.dart';

class AuthForm extends StatelessWidget {
  const AuthForm({
    super.key,
    required this.onSubmit,
  });

  final void Function(String email, String password) onSubmit;

  @override
  Widget build(BuildContext context) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    return Column(
      children: [
        TextField(
          controller: emailController,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => onSubmit(
            emailController.text,
            passwordController.text,
          ),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
