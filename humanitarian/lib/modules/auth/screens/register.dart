import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../widgets/auth_ui.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  String email = '', password = '', confirmPassword = '';
  bool loading = false;
  bool showPassword = false;

  void _onSubmit() async {
    if (_formKey.currentState!.validate()) {
      setState(() => loading = true);
      await Future.delayed(const Duration(milliseconds: 650));
      setState(() => loading = false);
      // Use Get for seamless routing
      Get.toNamed('/verify');
    }
  }

  // #39 — pop back to Login (keeps the stack, unlike the old offAllNamed)
  // with a fallback if Register was somehow opened with nothing to pop to.
  void _goToLogin() {
    if (Navigator.of(context).canPop()) {
      Get.back();
    } else {
      Get.offNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      height: 1.1,
    );

    final subtitleStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: Colors.white.withValues(alpha: 0.78),
      height: 1.5,
    );

    return AuthScaffold(
      child: AuthGlassCard(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: AuthBadge(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Create your account',
              ),
            ),
            const SizedBox(height: 28),
            Text('Join the platform'.tr, style: titleStyle),
            const SizedBox(height: 10),
            Text(
              'Create your account to support communities, track your actions, and stay connected to every mission.'
                  .tr,
              style: subtitleStyle,
            ),
            const SizedBox(height: 28),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FormLabel(text: 'Email address'),
                  const SizedBox(height: 10),
                  TextFormField(
                    enabled: !loading,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: authInputDecoration(
                      label: 'Email',
                      hintText: 'name@example.com',
                      icon: Icons.mail_outline_rounded,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (val) {
                      if (val == null || val.isEmpty || !val.contains('@')) {
                        return 'Enter a valid email'.tr;
                      }
                      return null;
                    },
                    onChanged: (v) => email = v,
                  ),
                  const SizedBox(height: 18),
                  _FormLabel(text: 'Password'),
                  const SizedBox(height: 10),
                  TextFormField(
                    enabled: !loading,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: authInputDecoration(
                      label: 'Password',
                      hintText: 'At least 6 characters',
                      icon: Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        icon: Icon(
                          showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white70,
                        ),
                        onPressed: () => setState(() {
                          showPassword = !showPassword;
                        }),
                      ),
                    ),
                    obscureText: !showPassword,
                    validator: (val) {
                      if (val == null || val.length < 6) {
                        return 'Password must be at least 6 characters'.tr;
                      }
                      return null;
                    },
                    onChanged: (v) => password = v,
                  ),
                  const SizedBox(height: 18),
                  _FormLabel(text: 'Confirm password'),
                  const SizedBox(height: 10),
                  TextFormField(
                    enabled: !loading,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: authInputDecoration(
                      label: 'Confirm Password',
                      hintText: 'Repeat your password',
                      icon: Icons.verified_user_outlined,
                    ),
                    obscureText: !showPassword,
                    validator: (val) {
                      if (val != password) {
                        return 'Passwords do not match'.tr;
                      }
                      return null;
                    },
                    onChanged: (v) => confirmPassword = v,
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0B385D),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        elevation: 0,
                      ),
                      onPressed: loading ? null : _onSubmit,
                      child: loading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                color: Color(0xFF0B385D),
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text('Create account'.tr),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                // #39 — pop back to Login (keeps the stack, unlike the old
                // offAllNamed) with a fallback if Register was somehow
                // opened with nothing to pop to.
                onPressed: loading ? null : _goToLogin,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text('Already have an account? Sign in'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.tr,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.92),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
