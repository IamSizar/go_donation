import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/registration_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/auth_navigation.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// New-user onboarding form. Replaces the old "Choose your role" screen:
/// collects name, date of birth, address and role, then submits the whole
/// thing to the admin for approval.
class RegistrationFormPage extends StatefulWidget {
  const RegistrationFormPage({super.key});

  @override
  State<RegistrationFormPage> createState() => _RegistrationFormPageState();
}

class _RegistrationFormPageState extends State<RegistrationFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  DateTime? _dob;
  int? _roleId;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefill when editing after a rejection (or completing a grandfathered
    // account) so the user doesn't retype everything. Skip the auto-generated
    // "User 1234" login fallback (last-4-of-phone) — that's not a real name.
    final storedName = sharedPreferences.getString('name_user') ?? '';
    _nameController.text =
        RegExp(r'^User \d+$').hasMatch(storedName) ? '' : storedName;
    _addressController.text = sharedPreferences.getString('address_user') ?? '';
    final rid = int.tryParse(sharedPreferences.getString('role_id') ?? '');
    if (rid != null && rid >= 1 && rid <= 3) _roleId = rid;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk) return;
    if (_roleId == null) {
      setState(() => _error = 'Please select your role'.tr);
      return;
    }
    AppHaptics.selection();
    setState(() => _loading = true);
    final res = await submitRegistration(
      fullName: _nameController.text.trim(),
      dateOfBirth: _dob == null ? '' : _fmt(_dob!),
      address: _addressController.text.trim(),
      roleId: _roleId!,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.ok) {
      AppHaptics.success();
      // pending -> waiting screen; approved (grandfathered) -> home.
      routeByRegistrationStatus(res.status);
    } else {
      AppHaptics.error();
      setState(() {
        _error = (res.error != null && res.error!.trim().isNotEmpty)
            ? res.error
            : 'Could not submit your registration. Please try again.'.tr;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScreen(
      child: SafeArea(
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: _loading,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PageTopBar(
                        title: 'Complete your registration',
                        hideBack: true,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tell us about yourself so an admin can review your account.'
                            .tr,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.5,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                      const SizedBox(height: 18),
                      GlassPanel(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label(context, 'Your full name'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                hintText: 'Your full name'.tr,
                                prefixIcon: const Icon(Icons.person_outline),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Please enter your name'.tr
                                      : null,
                            ),
                            const SizedBox(height: 16),
                            _label(context, 'Date of birth'),
                            const SizedBox(height: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: _pickDate,
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  prefixIcon:
                                      const Icon(Icons.cake_outlined),
                                ),
                                child: Text(
                                  _dob == null
                                      ? 'Select date'.tr
                                      : _fmt(_dob!),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: _dob == null
                                        ? AppThemeConfig.mutedText(context)
                                        : AppThemeConfig.text(context),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _label(context, 'Your address'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _addressController,
                              minLines: 1,
                              maxLines: 3,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                hintText: 'Your address'.tr,
                                prefixIcon:
                                    const Icon(Icons.location_on_outlined),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Please enter your address'.tr
                                      : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _label(context, 'Select your role'),
                      const SizedBox(height: 10),
                      _RoleTile(
                        icon: Icons.volunteer_activism_rounded,
                        color: Colors.amber,
                        label: 'Donor',
                        tagline: 'Give and support causes',
                        selected: _roleId == 1,
                        onTap: () => setState(() => _roleId = 1),
                      ),
                      const SizedBox(height: 10),
                      _RoleTile(
                        icon: Icons.family_restroom_rounded,
                        color: Colors.deepOrangeAccent,
                        label: 'Beneficiary',
                        tagline: 'Receive aid and support',
                        selected: _roleId == 2,
                        onTap: () => setState(() => _roleId = 2),
                      ),
                      const SizedBox(height: 10),
                      _RoleTile(
                        icon: Icons.handshake_rounded,
                        color: Colors.lightBlue,
                        label: 'Volunteer',
                        tagline: 'Help on the ground',
                        selected: _roleId == 3,
                        onTap: () => setState(() => _roleId = 3),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: Text('Submit for approval'.tr),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_loading)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.15),
                  child: const Center(
                    child: CircularProgressIndicator.adaptive(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
        text.tr,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: AppThemeConfig.mutedText(context),
        ),
      );
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.tagline,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String tagline;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeConfig.surface(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppThemeConfig.primary
                  : AppThemeConfig.border(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tagline.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? AppThemeConfig.primary
                    : AppThemeConfig.mutedText(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
