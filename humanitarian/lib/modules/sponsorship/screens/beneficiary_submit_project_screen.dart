import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/api/project_categories_api.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/beneficiary_submit_project_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Form for beneficiaries to propose a new help project (e.g. “Water for all”).
/// Submits via [BeneficiarySubmitProjectController] (endpoint in `api/links.dart`).
class BeneficiarySubmitProjectScreen extends StatefulWidget {
  const BeneficiarySubmitProjectScreen({super.key});

  @override
  State<BeneficiarySubmitProjectScreen> createState() =>
      _BeneficiarySubmitProjectScreenState();
}

class _BeneficiarySubmitProjectScreenState
    extends State<BeneficiarySubmitProjectScreen> {
  final _formKey = GlobalKey<FormState>();

  late final BeneficiarySubmitProjectController _submitController;

  // #17 — admin-managed project categories for the dropdown (empty = free-text
  // fallback while loading or offline).
  List<ProjectCategory> _categories = const [];
  ProjectCategory? _selectedCategory;

  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _summaryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _currencyController = TextEditingController(text: 'IQD');
  final _locationController = TextEditingController();
  final _beneficiaryNameController = TextEditingController();
  final _peopleAffectedController = TextEditingController();
  final _maleCountController = TextEditingController();
  final _femaleCountController = TextEditingController();
  final _volunteerAgeProfileController = TextEditingController();
  final _volunteerSkillsController = TextEditingController();
  final _peopleVolunteerDescriptionController = TextEditingController();
  final _timelineController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _submitController = Get.put(BeneficiarySubmitProjectController());
    _peopleAffectedController.addListener(_onPeopleAffectedChanged);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await fetchProjectCategories();
    if (!mounted) return;
    setState(() => _categories = cats);
  }

  void _onPeopleAffectedChanged() {
    if (mounted) setState(() {});
  }

  // #17 — CMS-fed category dropdown; graceful free-text fallback while loading
  // or when the list is empty/offline so the form is always usable.
  Widget _buildCategoryField(BuildContext context) {
    if (_categories.isEmpty) {
      return TextFormField(
        controller: _categoryController,
        textInputAction: TextInputAction.next,
        style: TextStyle(color: AppThemeConfig.text(context)),
        decoration: _fieldDecoration(
          context,
          hintText: 'e.g. Water, Health, Education, Shelter',
          icon: Icons.category_rounded,
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) {
            return 'Enter a category'.tr;
          }
          return null;
        },
      );
    }
    return DropdownButtonFormField<ProjectCategory>(
      initialValue: _selectedCategory,
      isExpanded: true,
      style: TextStyle(color: AppThemeConfig.text(context)),
      decoration: _fieldDecoration(
        context,
        hintText: 'Select a category',
        icon: Icons.category_rounded,
      ),
      hint: Text(
        'Select a category'.tr,
        style: TextStyle(color: AppThemeConfig.mutedText(context)),
      ),
      items: [
        for (final c in _categories)
          DropdownMenuItem<ProjectCategory>(
            value: c,
            child: Text(c.localizedName),
          ),
      ],
      onChanged: (c) {
        setState(() {
          _selectedCategory = c;
          _categoryController.text = c?.localizedName ?? '';
        });
      },
      validator: (v) => v == null ? 'Enter a category'.tr : null,
    );
  }

  void _clearForm() {
    _titleController.clear();
    _categoryController.clear();
    _summaryController.clear();
    _descriptionController.clear();
    _amountController.clear();
    _currencyController.text = 'IQD';
    _locationController.clear();
    _beneficiaryNameController.clear();
    _peopleAffectedController.clear();
    _maleCountController.clear();
    _femaleCountController.clear();
    _volunteerAgeProfileController.clear();
    _volunteerSkillsController.clear();
    _peopleVolunteerDescriptionController.clear();
    _timelineController.clear();
    _contactNameController.clear();
    _contactPhoneController.clear();
    _contactEmailController.clear();
    _notesController.clear();
    _formKey.currentState?.reset();
    if (mounted) setState(() {});
  }

  bool get _showPeopleDetailFields =>
      _peopleAffectedController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _peopleAffectedController.removeListener(_onPeopleAffectedChanged);
    _titleController.dispose();
    _categoryController.dispose();
    _summaryController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    _currencyController.dispose();
    _locationController.dispose();
    _beneficiaryNameController.dispose();
    _peopleAffectedController.dispose();
    _maleCountController.dispose();
    _femaleCountController.dispose();
    _volunteerAgeProfileController.dispose();
    _volunteerSkillsController.dispose();
    _peopleVolunteerDescriptionController.dispose();
    _timelineController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String hintText,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hintText.tr,
      hintStyle: TextStyle(color: AppThemeConfig.mutedText(context)),
      prefixIcon: Icon(icon, color: AppThemeConfig.mutedText(context)),
      filled: true,
      fillColor: AppThemeConfig.softSurface(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: AppThemeConfig.border(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: AppThemeConfig.border(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: AppThemeConfig.primary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final amount = double.parse(_amountController.text.trim());

    final err = await _submitController.submitProjectRequest(
      title: _titleController.text,
      category: _categoryController.text,
      summary: _summaryController.text,
      description: _descriptionController.text,
      amount: amount,
      currency: _currencyController.text,
      location: _locationController.text,
      beneficiaryName: _beneficiaryNameController.text,
      peopleAffected: _peopleAffectedController.text,
      maleCount: _maleCountController.text,
      femaleCount: _femaleCountController.text,
      volunteerAgeProfile: _volunteerAgeProfileController.text,
      volunteerSkills: _volunteerSkillsController.text,
      peopleVolunteerDescription: _peopleVolunteerDescriptionController.text,
      timeline: _timelineController.text,
      contactName: _contactNameController.text,
      contactPhone: _contactPhoneController.text,
      contactEmail: _contactEmailController.text,
      notes: _notesController.text,
    );

    if (!mounted) return;

    if (err != null) {
      Get.snackbar(
        'Submit failed'.tr,
        err,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
      return;
    }

    final id = _submitController.lastSubmittedId.value;
    final message = id != null
        ? 'Your project is pending review (reference #@id).'.trParams({
            'id': '$id',
          })
        : 'Your project is pending review.'.tr;

    _clearForm();
    Get.back<void>();
    Get.snackbar(
      'Request submitted'.tr,
      message,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 5),
      margin: const EdgeInsets.all(16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Submit a project for help',
      subtitle:
          'Describe your initiative in your own language. Admin can add the other translations later.',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Example: “Clean water for Al-Mafraq village” — state the goal, who benefits, and the total budget you need.'
                        .tr,
                    style: TextStyle(
                      color: AppThemeConfig.mutedText(context),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionLabel(title: 'Project'),
            const SizedBox(height: 12),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LabeledField(
                    label: 'Project title',
                    child: TextFormField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText: 'e.g. Water for all — community wells',
                        icon: Icons.title_rounded,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter a project title'.tr;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabeledField(
                    label: 'Category / type',
                    child: _buildCategoryField(context),
                  ),
                  const SizedBox(height: 14),
                  _LabeledField(
                    label: 'Short summary (one or two sentences)',
                    child: TextFormField(
                      controller: _summaryController,
                      textInputAction: TextInputAction.next,
                      maxLines: 2,
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText: 'What you want to achieve in brief',
                        icon: Icons.short_text_rounded,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter a short summary'.tr;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabeledField(
                    label: 'Full description — how the money will be used',
                    child: TextFormField(
                      controller: _descriptionController,
                      textInputAction: TextInputAction.newline,
                      minLines: 4,
                      maxLines: 8,
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText:
                            'Materials, labor, partners, timeline steps, transparency…',
                        icon: Icons.description_rounded,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Describe the project in detail'.tr;
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionLabel(title: 'Budget'),
            const SizedBox(height: 12),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _LabeledField(
                          label: 'Amount needed (number)',
                          child: TextFormField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            style: TextStyle(
                              color: AppThemeConfig.text(context),
                            ),
                            decoration: _fieldDecoration(
                              context,
                              hintText: 'e.g. 5000',
                              icon: Icons.payments_rounded,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Enter the amount needed'.tr;
                              }
                              final n = double.tryParse(v.trim());
                              if (n == null || n <= 0) {
                                return 'Enter a valid amount'.tr;
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _LabeledField(
                          label: 'Currency',
                          child: TextFormField(
                            controller: _currencyController,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.characters,
                            style: TextStyle(
                              color: AppThemeConfig.text(context),
                            ),
                            decoration: _fieldDecoration(
                              context,
                              hintText: 'IQD',
                              icon: Icons.currency_exchange_rounded,
                            ),
                            readOnly: true,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Enter currency'.tr;
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionLabel(title: 'Where & who'),
            const SizedBox(height: 12),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LabeledField(
                    label: 'Location / area served',
                    child: TextFormField(
                      controller: _locationController,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText: 'Village, city, region',
                        icon: Icons.place_rounded,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter the location'.tr;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabeledField(
                    label: 'Beneficiary or community name'.tr,
                    child: TextFormField(
                      controller: _beneficiaryNameController,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText: 'Who will benefit from this project',
                        icon: Icons.groups_rounded,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter beneficiary or community'.tr;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabeledField(
                    label: 'Approx. number of people affected (optional)',
                    child: TextFormField(
                      controller: _peopleAffectedController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText: 'e.g. 250',
                        icon: Icons.people_outline_rounded,
                      ),
                    ),
                  ),
                  if (_showPeopleDetailFields) ...[
                    const SizedBox(height: 18),
                    Text(
                      'You entered a headcount — add a gender split, volunteer profile, and skills in free text so coordinators can plan teams (all optional below).'
                          .tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.45,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _LabeledField(
                            label: 'Male (count, optional)',
                            child: TextFormField(
                              controller: _maleCountController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: TextStyle(
                                color: AppThemeConfig.text(context),
                              ),
                              decoration: _fieldDecoration(
                                context,
                                hintText: 'e.g. 120',
                                icon: Icons.man_2_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _LabeledField(
                            label: 'Female (count, optional)',
                            child: TextFormField(
                              controller: _femaleCountController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: TextStyle(
                                color: AppThemeConfig.text(context),
                              ),
                              decoration: _fieldDecoration(
                                context,
                                hintText: 'e.g. 130',
                                icon: Icons.woman_2_outlined,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _LabeledField(
                      label:
                          'Volunteer age profile (type freely — e.g. mostly 20 years old, mixed ages 18–45)',
                      child: TextFormField(
                        controller: _volunteerAgeProfileController,
                        textInputAction: TextInputAction.next,
                        maxLines: 2,
                        style: TextStyle(color: AppThemeConfig.text(context)),
                        decoration: _fieldDecoration(
                          context,
                          hintText:
                              'Describe typical ages of people who can volunteer',
                          icon: Icons.cake_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _LabeledField(
                      label:
                          'Skills & what volunteers know (e.g. computers, Arabic/English, construction)',
                      child: TextFormField(
                        controller: _volunteerSkillsController,
                        textInputAction: TextInputAction.next,
                        minLines: 2,
                        maxLines: 4,
                        style: TextStyle(color: AppThemeConfig.text(context)),
                        decoration: _fieldDecoration(
                          context,
                          hintText:
                              'List literacy, languages, tools, certifications…',
                          icon: Icons.psychology_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _LabeledField(
                      label:
                          'Extra description — people, volunteers, or any typed data',
                      child: TextFormField(
                        controller: _peopleVolunteerDescriptionController,
                        textInputAction: TextInputAction.newline,
                        minLines: 3,
                        maxLines: 6,
                        style: TextStyle(color: AppThemeConfig.text(context)),
                        decoration: _fieldDecoration(
                          context,
                          hintText:
                              'Anything else: roles needed, availability, special needs, education level…',
                          icon: Icons.notes_rounded,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _LabeledField(
                    label: 'Timeline or target date (optional)',
                    child: TextFormField(
                      controller: _timelineController,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText: 'e.g. Complete before winter 2026',
                        icon: Icons.event_note_rounded,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionLabel(title: 'Contact (for coordinators)'),
            const SizedBox(height: 12),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LabeledField(
                    label: 'Contact person name (optional)',
                    child: TextFormField(
                      controller: _contactNameController,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText: 'Your name or organization representative',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabeledField(
                    label: 'Phone (optional)',
                    child: TextFormField(
                      controller: _contactPhoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText: '+962 …',
                        icon: Icons.phone_rounded,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final t = v.replaceAll(RegExp(r'[\s()-]'), '');
                        if (t.length < 8) {
                          return 'Enter a valid phone or leave empty'.tr;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabeledField(
                    label: 'Email (optional)',
                    child: TextFormField(
                      controller: _contactEmailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText: 'name@example.com',
                        icon: Icons.email_outlined,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        if (!v.contains('@') || v.trim().length < 5) {
                          return 'Enter a valid email or leave empty'.tr;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabeledField(
                    label: 'Other notes (optional)',
                    child: TextFormField(
                      controller: _notesController,
                      minLines: 2,
                      maxLines: 4,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: AppThemeConfig.text(context)),
                      decoration: _fieldDecoration(
                        context,
                        hintText: 'Partners, documents, risks, links…',
                        icon: Icons.note_alt_outlined,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Obx(() {
                final loading = _submitController.isSubmitting.value;
                return FilledButton(
                  onPressed: loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: loading
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          'Submit project request'.tr,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.tr,
          style: TextStyle(
            color: AppThemeConfig.text(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
