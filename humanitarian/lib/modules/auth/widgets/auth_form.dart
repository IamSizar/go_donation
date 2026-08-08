import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AuthForm extends StatelessWidget {
  const AuthForm({super.key, required this.onSubmit});

  final void Function(String email, String password) onSubmit;

  @override
  Widget build(BuildContext context) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    return Column(
      children: [
        TextField(
          controller: emailController,
          decoration: InputDecoration(labelText: 'Email'.tr),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: InputDecoration(labelText: 'Password'.tr),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () =>
              onSubmit(emailController.text, passwordController.text),
          child: Text('Continue'.tr),
        ),
      ],
    );
  }
}
