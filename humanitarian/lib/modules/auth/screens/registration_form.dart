import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/registration_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/auth_navigation.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/legal/screens/terms_screen.dart';
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
  final _cityController = TextEditingController();
  final _occupationController = TextEditingController();
  String? _gender; // #39 — optional: Male | Female | Other
  final _familySizeController = TextEditingController(); // #40 — eligible
  final _incomeController = TextEditingController();
  String? _housingStatus; // owned | rented | hosted | displaced
  final _skillsController = TextEditingController(); // #41 — volunteer
  final _availabilityController = TextEditingController();
  String? _experience; // none | lt1 | y1to3 | gt3
  DateTime? _dob;
  int? _roleId;
  bool _loading = false;
  String? _error;
  bool _agreeToTerms = false;
  Set<String> _required = {}; // #43 — admin-configured required optional fields

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
    // #43 — load admin-configured required fields.
    fetchRequiredFields().then((s) {
      if (mounted) setState(() => _required = s);
    });
  }

  // #43 — returns the label key of the first required-but-empty field, or null.
  String? _firstMissingRequired() {
    bool blank(String v) => v.trim().isEmpty;
    final checks = <String, ({bool applies, bool filled, String labelKey})>{
      'gender': (applies: true, filled: _gender != null, labelKey: 'reg_gender'),
      'date_of_birth': (applies: true, filled: _dob != null, labelKey: 'Date of birth'),
      'city': (applies: true, filled: !blank(_cityController.text), labelKey: 'reg_city'),
      'occupation': (applies: true, filled: !blank(_occupationController.text), labelKey: 'reg_occupation'),
      'family_size': (applies: _roleId == 2, filled: !blank(_familySizeController.text), labelKey: 'reg_family_size'),
      'housing_status': (applies: _roleId == 2, filled: _housingStatus != null, labelKey: 'reg_housing'),
      'monthly_income': (applies: _roleId == 2, filled: !blank(_incomeController.text), labelKey: 'reg_income'),
      'skills': (applies: _roleId == 3, filled: !blank(_skillsController.text), labelKey: 'reg_skills'),
      'availability': (applies: _roleId == 3, filled: !blank(_availabilityController.text), labelKey: 'reg_availability'),
      'experience': (applies: _roleId == 3, filled: _experience != null, labelKey: 'reg_experience'),
    };
    for (final key in _required) {
      final c = checks[key];
      if (c != null && c.applies && !c.filled) return c.labelKey;
    }
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _occupationController.dispose();
    _familySizeController.dispose();
    _incomeController.dispose();
    _skillsController.dispose();
    _availabilityController.dispose();
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
    if (!_agreeToTerms) {
      setState(
        () => _error = 'Please accept the Terms & Conditions to continue'.tr,
      );
      return;
    }
    // #43 — enforce admin-configured required fields.
    final missing = _firstMissingRequired();
    if (missing != null) {
      setState(() => _error = '${missing.tr}: ${'reg_required_missing'.tr}');
      return;
    }
    AppHaptics.selection();
    setState(() => _loading = true);
    final res = await submitRegistration(
      fullName: _nameController.text.trim(),
      dateOfBirth: _dob == null ? '' : _fmt(_dob!),
      address: _addressController.text.trim(),
      roleId: _roleId!,
      gender: _gender ?? '',
      city: _cityController.text.trim(),
      occupation: _occupationController.text.trim(),
      familySize: _roleId == 2 ? _familySizeController.text.trim() : '',
      housingStatus: _roleId == 2 ? (_housingStatus ?? '') : '',
      monthlyIncome: _roleId == 2 ? _incomeController.text.trim() : '',
      skills: _roleId == 3 ? _skillsController.text.trim() : '',
      availability: _roleId == 3 ? _availabilityController.text.trim() : '',
      experience: _roleId == 3 ? (_experience ?? '') : '',
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
                            // #39 — fuller sign-up fields (all optional).
                            const SizedBox(height: 16),
                            _label(context, 'reg_gender'),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: _gender,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.wc_outlined),
                              ),
                              hint: Text('reg_gender_hint'.tr),
                              items: [
                                for (final g in const ['Male', 'Female', 'Other'])
                                  DropdownMenuItem(value: g, child: Text(g.tr)),
                              ],
                              onChanged: (v) => setState(() => _gender = v),
                            ),
                            const SizedBox(height: 16),
                            _label(context, 'reg_city'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _cityController,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                hintText: 'reg_city_hint'.tr,
                                prefixIcon: const Icon(Icons.location_city_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _label(context, 'reg_occupation'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _occupationController,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                hintText: 'reg_occupation_hint'.tr,
                                prefixIcon: const Icon(Icons.work_outline),
                              ),
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
                      // #40 — eligible (beneficiary) sign-up: extra fields.
                      if (_roleId == 2) ...[
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_eligible_section'),
                              const SizedBox(height: 12),
                              _label(context, 'reg_family_size'),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _familySizeController,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  hintText: 'reg_family_size_hint'.tr,
                                  prefixIcon: const Icon(Icons.group_outlined),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _label(context, 'reg_housing'),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: _housingStatus,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.home_outlined),
                                ),
                                hint: Text('reg_housing_hint'.tr),
                                items: [
                                  for (final h in const ['owned', 'rented', 'hosted', 'displaced'])
                                    DropdownMenuItem(value: h, child: Text('housing_$h'.tr)),
                                ],
                                onChanged: (v) => setState(() => _housingStatus = v),
                              ),
                              const SizedBox(height: 16),
                              _label(context, 'reg_income'),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _incomeController,
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  hintText: 'reg_income_hint'.tr,
                                  prefixIcon: const Icon(Icons.payments_outlined),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // #41 — volunteer/employee sign-up: extra fields.
                      if (_roleId == 3) ...[
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_volunteer_section'),
                              const SizedBox(height: 12),
                              _label(context, 'reg_skills'),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _skillsController,
                                minLines: 1,
                                maxLines: 3,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  hintText: 'reg_skills_hint'.tr,
                                  prefixIcon: const Icon(Icons.star_outline),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _label(context, 'reg_availability'),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _availabilityController,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  hintText: 'reg_availability_hint'.tr,
                                  prefixIcon: const Icon(Icons.schedule_outlined),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _label(context, 'reg_experience'),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: _experience,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                hint: Text('reg_experience_hint'.tr),
                                items: [
                                  for (final e in const ['none', 'lt1', 'y1to3', 'gt3'])
                                    DropdownMenuItem(value: e, child: Text('exp_$e'.tr)),
                                ],
                                onChanged: (v) => setState(() => _experience = v),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: Checkbox(
                              value: _agreeToTerms,
                              onChanged: (v) =>
                                  setState(() => _agreeToTerms = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Get.to(() => const TermsScreen()),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      color: AppThemeConfig.mutedText(context),
                                      fontSize: 13.5,
                                    ),
                                    children: [
                                      TextSpan(text: 'I agree to the '.tr),
                                      TextSpan(
                                        text: 'Terms & Conditions'.tr,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          decoration: TextDecoration.underline,
                                          color: AppThemeConfig.text(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
