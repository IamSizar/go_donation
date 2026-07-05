import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/registration_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/auth_navigation.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Shown to a user whose registration is awaiting (or was refused by) admin
/// review. They cannot enter the app from here — only re-check status, edit &
/// resubmit (if rejected), or log out. If a status poll comes back approved,
/// the router moves them on automatically.
class PendingApprovalPage extends StatefulWidget {
  const PendingApprovalPage({super.key});

  @override
  State<PendingApprovalPage> createState() => _PendingApprovalPageState();
}

class _PendingApprovalPageState extends State<PendingApprovalPage> {
  bool _checking = false;

  String get _status =>
      (sharedPreferences.getString('registration_status') ?? 'pending').trim();
  String? get _reason => sharedPreferences.getString('reject_reason');

  bool get _rejected => _status == 'rejected';

  @override
  void initState() {
    super.initState();
    // Refresh once on open in case the admin already decided.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(silent: true));
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    final body = await fetchRegistrationStatus();
    if (!mounted) return;
    setState(() => _checking = false);
    final status = (body?['registration_status'] ?? _status).toString();
    if (status == 'approved') {
      routeByRegistrationStatus('approved');
      return;
    }
    if (!silent) {
      if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
      Get.snackbar(
        'Pending approval'.tr,
        'Still waiting for approval. Please check back soon.'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    setState(() {}); // reflect a possible pending->rejected transition
  }

  Future<void> _logout() async {
    // 27.4/27.5 — leave this screen first, then revoke server-side + clear all
    // local session/identity/guest state via the unified logout().
    Get.offAllNamed(AppRoutes.authLogin);
    await logout();
  }

  String? _roleLabel() {
    switch (int.tryParse(sharedPreferences.getString('role_id') ?? '')) {
      case 1:
        return 'Contributor';
      case 2:
        return 'Recipient';
      case 3:
        return 'Volunteer';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rejected = _rejected;
    final accent = rejected ? Colors.orangeAccent : AppThemeConfig.primary;

    return GradientScreen(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.14),
                    border: Border.all(color: accent.withValues(alpha: 0.4)),
                  ),
                  child: Icon(
                    rejected
                        ? Icons.error_outline_rounded
                        : Icons.hourglass_top_rounded,
                    color: accent,
                    size: 46,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                (rejected ? 'Registration needs changes' : 'Awaiting admin review')
                    .tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppThemeConfig.text(context),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                (rejected
                        ? 'Your registration was not approved. Please update your details and submit again.'
                        : 'Your registration was submitted. You can sign in once an admin approves your account.')
                    .tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: AppThemeConfig.mutedText(context),
                ),
              ),
              const SizedBox(height: 20),
              if (rejected &&
                  _reason != null &&
                  _reason!.trim().isNotEmpty) ...[
                GlassPanel(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rejection reason'.tr,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _reason!,
                        style: TextStyle(
                          fontSize: 15,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your details'.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _row(context, 'Your full name',
                        sharedPreferences.getString('name_user')),
                    _row(context, 'Your address',
                        sharedPreferences.getString('address_user')),
                    _row(context, 'Select your role', _roleLabel()),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (rejected)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Get.offAllNamed(AppRoutes.registration),
                    child: Text('Edit and resubmit'.tr),
                  ),
                ),
              if (rejected) const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _checking ? null : () => _check(),
                  child: _checking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('Check status'.tr),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _logout,
                  child: Text('Log out'.tr),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label.tr,
              style: TextStyle(
                fontSize: 13,
                color: AppThemeConfig.mutedText(context),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value.tr,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppThemeConfig.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
