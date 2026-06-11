import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/proposal/controllers/beneficiary_cases_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/beneficiary_case_detail_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/sponsorships_controller.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/sponsorship_overview_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class ProposalServicesSection extends StatelessWidget {
  const ProposalServicesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final roleId = sharedPreferences.getString('role_id') ?? '';
    return SectionScaffold(
      title: 'Services',
      subtitle: _servicesSubtitleForRole(roleId),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        children: [_servicesForRole(roleId)],
      ),
    );
  }
}

String _servicesSubtitleForRole(String roleId) {
  return switch (roleId) {
    '2' => 'Your requests, public updates, and support tools.',
    '3' => 'Volunteer reports, public updates, and support tools.',
    _ => 'Giving tools, public updates, reports, and support.',
  };
}

Widget _servicesForRole(String roleId) {
  return switch (roleId) {
    '2' => const _BeneficiaryServices(),
    '3' => const _VolunteerServices(),
    _ => const _DonorServices(),
  };
}

class _BeneficiaryServices extends StatelessWidget {
  const _BeneficiaryServices();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // "Submit beneficiary case" intentionally lives only in the Kafala /
        // Beneficiary-support tab, where it sits next to "My beneficiary cases"
        // tracking — so it is not duplicated here in Services.
        SectionTile(
          icon: Icons.diversity_1_rounded,
          title: 'Marriage service',
          subtitle: 'Create or review private marriage service requests.',
          color: Colors.deepPurple,
          onTap: () => Get.to(() => const MarriageProfileFormScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.apartment_rounded,
          title: 'Partners',
          subtitle: 'Browse partner and supporting entities.',
          color: Colors.blueAccent,
          onTap: () => Get.to(() => const PartnersScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.article_rounded,
          title: 'News and activities',
          subtitle: 'See activities, news, articles, and events.',
          color: Colors.orange,
          onTap: () => Get.to(() => const NewsActivitiesScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.support_agent_rounded,
          title: 'Technical support',
          subtitle: 'Send a support request to the institution.',
          color: Colors.indigo,
          onTap: () => Get.to(() => const SupportTicketFormScreen()),
        ),
      ],
    );
  }
}

class _DonorServices extends StatelessWidget {
  const _DonorServices();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionTile(
          icon: Icons.verified_user_rounded,
          title: 'Beneficiary cases',
          subtitle: 'Review verified cases by code, need, and priority.',
          color: Colors.teal,
          onTap: () => Get.to(() => const BeneficiaryCasesScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.handshake_rounded,
          title: 'Create sponsorship',
          subtitle: 'Register a scheduled sponsorship commitment.',
          color: Colors.pinkAccent,
          onTap: () => Get.to(() => const SponsorshipFormScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.inventory_2_rounded,
          title: 'In-kind donation',
          subtitle: 'Submit food, clothing, supplies, or other items.',
          color: Colors.green,
          onTap: () => Get.to(() => const InKindDonationFormScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.apartment_rounded,
          title: 'Partners',
          subtitle: 'Browse partner and supporting entities.',
          color: Colors.blueAccent,
          onTap: () => Get.to(() => const PartnersScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.article_rounded,
          title: 'News and activities',
          subtitle: 'See activities, news, articles, and events.',
          color: Colors.orange,
          onTap: () => Get.to(() => const NewsActivitiesScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.support_agent_rounded,
          title: 'Technical support',
          subtitle: 'Send a support request to the institution.',
          color: Colors.indigo,
          onTap: () => Get.to(() => const SupportTicketFormScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.query_stats_rounded,
          title: 'Reports',
          subtitle: 'View donation, case, project, and expense totals.',
          color: Colors.cyan,
          onTap: () => Get.to(() => const ReportsScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.diversity_1_rounded,
          title: 'Marriage service',
          subtitle: 'Create or review private marriage service requests.',
          color: Colors.deepPurple,
          onTap: () => Get.to(() => const MarriageProfileFormScreen()),
        ),
      ],
    );
  }
}

class _VolunteerServices extends StatelessWidget {
  const _VolunteerServices();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionTile(
          icon: Icons.query_stats_rounded,
          title: 'Reports',
          subtitle:
              'View volunteer attendance, mission, and completion totals.',
          color: Colors.cyan,
          onTap: () => Get.to(() => const ReportsScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.apartment_rounded,
          title: 'Partners',
          subtitle: 'Browse partner and supporting entities.',
          color: Colors.blueAccent,
          onTap: () => Get.to(() => const PartnersScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.article_rounded,
          title: 'News and activities',
          subtitle: 'See activities, news, articles, and events.',
          color: Colors.orange,
          onTap: () => Get.to(() => const NewsActivitiesScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.support_agent_rounded,
          title: 'Technical support',
          subtitle: 'Send a support request to the institution.',
          color: Colors.indigo,
          onTap: () => Get.to(() => const SupportTicketFormScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.diversity_1_rounded,
          title: 'Marriage service',
          subtitle: 'Create or review private marriage service requests.',
          color: Colors.deepPurple,
          onTap: () => Get.to(() => const MarriageProfileFormScreen()),
        ),
      ],
    );
  }
}

class BeneficiaryCasesScreen extends StatelessWidget {
  const BeneficiaryCasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<BeneficiaryCasesController>()
        ? Get.find<BeneficiaryCasesController>()
        : Get.put(BeneficiaryCasesController());

    return SectionScaffold(
      title: 'Beneficiary cases',
      subtitle: 'Verified public case records.',
      child: Obx(() {
        final items = controller.cases;
        return RefreshIndicator(
          onRefresh: controller.fetchCases,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              if (controller.isLoading.value)
                const Center(child: CircularProgressIndicator()),
              if (controller.errorMessage.value != null)
                SectionTile(
                  icon: Icons.verified_user_rounded,
                  title: 'Beneficiary cases',
                  subtitle: controller.errorMessage.value!,
                  color: Colors.teal,
                  onTap: controller.fetchCases,
                ),
              if (!controller.isLoading.value &&
                  controller.errorMessage.value == null &&
                  items.isEmpty)
                const SectionTile(
                  icon: Icons.verified_user_rounded,
                  title: 'Beneficiary cases',
                  subtitle: 'No approved cases are available yet.',
                  color: Colors.teal,
                ),
              for (final item in items) ...[
                SectionTile(
                  icon: Icons.verified_user_rounded,
                  title: _localizedCaseTitle(item),
                  subtitle: _caseSubtitle(item),
                  color: Colors.teal,
                  onTap: () =>
                      Get.to(() => BeneficiaryCaseDetailScreen(caseItem: item)),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class MyBeneficiaryCasesScreen extends StatelessWidget {
  const MyBeneficiaryCasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<MyBeneficiaryCasesController>()
        ? Get.find<MyBeneficiaryCasesController>()
        : Get.put(MyBeneficiaryCasesController());

    return SectionScaffold(
      title: 'My beneficiary cases',
      subtitle: 'Track private case submissions and admin review status.',
      child: Obx(() {
        final items = controller.cases;
        return RefreshIndicator(
          onRefresh: controller.fetchCases,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              _CaseSummaryBand(items: items),
              const SizedBox(height: 14),
              if (controller.isLoading.value)
                const Center(child: CircularProgressIndicator()),
              if (controller.errorMessage.value != null)
                SectionTile(
                  icon: Icons.refresh_rounded,
                  title: 'My beneficiary cases',
                  subtitle: controller.errorMessage.value!,
                  color: Colors.teal,
                  onTap: controller.fetchCases,
                ),
              if (!controller.isLoading.value &&
                  controller.errorMessage.value == null &&
                  items.isEmpty)
                const SectionTile(
                  icon: Icons.assignment_ind_rounded,
                  title: 'No cases yet',
                  subtitle: 'Submitted beneficiary cases will appear here.',
                  color: Colors.teal,
                ),
              for (final item in items) ...[
                SectionTile(
                  icon: Icons.assignment_ind_rounded,
                  title: _localizedCaseTitle(item),
                  subtitle: _myCaseSubtitle(item),
                  color: _caseStatusColor(
                    (item['verification_status'] ?? '').toString(),
                  ),
                  onTap: () =>
                      Get.to(() => BeneficiaryCaseDetailScreen(caseItem: item)),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _CaseSummaryBand extends StatelessWidget {
  const _CaseSummaryBand({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final inReview = items.where((item) {
      final status = (item['verification_status'] ?? '').toString();
      return status == 'submitted' ||
          status == 'under_review' ||
          status == 'needs_changes';
    }).length;
    final approved = items
        .where(
          (item) =>
              (item['verification_status'] ?? '').toString() == 'approved',
        )
        .length;

    return GlassPanel(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          InfoChip(
            icon: Icons.assignment_ind_rounded,
            label: '${items.length} total',
          ),
          InfoChip(icon: Icons.schedule_rounded, label: '$inReview in review'),
          InfoChip(icon: Icons.verified_rounded, label: '$approved approved'),
        ],
      ),
    );
  }
}

String _localizedCaseTitle(Map<String, dynamic> item) {
  return localizedContentFromMap(
    item,
    'public_title',
    fallback: 'Beneficiary case',
  );
}

String _caseSubtitle(Map<String, dynamic> item) {
  return ['case_code', 'city', 'priority_level']
      .map((key) => (item[key] ?? '').toString())
      .where((value) => value.trim().isNotEmpty)
      .join(' - ');
}

String _myCaseSubtitle(Map<String, dynamic> item) {
  final status = (item['verification_status'] ?? 'submitted')
      .toString()
      .replaceAll('_', ' ');
  final base = _caseSubtitle(item);
  final notes = (item['review_notes'] ?? '').toString().trim();
  return [
    status,
    if (base.trim().isNotEmpty) base,
    if (notes.isNotEmpty) notes,
  ].join(' - ');
}

Color _caseStatusColor(String status) {
  return switch (status) {
    'approved' => Colors.green,
    'rejected' => Colors.redAccent,
    'under_review' || 'needs_changes' => Colors.orange,
    'submitted' || 'draft' => Colors.amber,
    _ => Colors.teal,
  };
}

String? _requiredText(String value, String message) {
  return value.trim().isEmpty ? message.tr : null;
}

bool _hasSignedInUser() {
  final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
  return userId != null && userId > 0;
}

enum ProposalLoader {
  beneficiaryCases,
  partners,
  media,
  sponsorships,
  marriage,
}

class ProposalListScreen extends StatelessWidget {
  const ProposalListScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.loader,
    required this.titleKey,
    required this.subtitleKeys,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final ProposalLoader loader;
  final String titleKey;
  final List<String> subtitleKeys;
  final IconData icon;
  final Color color;

  Future<List<Map<String, dynamic>>> _load() {
    const api = ModuleApi();
    return switch (loader) {
      ProposalLoader.beneficiaryCases => api.beneficiaryCases(),
      ProposalLoader.partners => api.partners(),
      ProposalLoader.media => api.mediaPosts(),
      ProposalLoader.sponsorships => api.sponsorships(),
      ProposalLoader.marriage => api.marriageProfiles(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: title,
      subtitle: subtitle,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _load(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator()),
              if (snapshot.hasError)
                SectionTile(
                  icon: icon,
                  title: title,
                  subtitle: 'Unable to load data from the server.',
                  color: color,
                ),
              if (!snapshot.hasError &&
                  snapshot.connectionState != ConnectionState.waiting &&
                  items.isEmpty)
                SectionTile(
                  icon: icon,
                  title: title,
                  subtitle: 'No records are available yet.',
                  color: color,
                ),
              for (final item in items) ...[
                SectionTile(
                  icon: icon,
                  title: (item[titleKey] ?? 'Record').toString(),
                  subtitle: subtitleKeys
                      .map((key) => (item[key] ?? '').toString())
                      .where((value) => value.trim().isNotEmpty)
                      .join(' - '),
                  color: color,
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class SponsorshipFormScreen extends StatefulWidget {
  const SponsorshipFormScreen({super.key});

  @override
  State<SponsorshipFormScreen> createState() => _SponsorshipFormScreenState();
}

class BeneficiaryCaseFormScreen extends StatefulWidget {
  const BeneficiaryCaseFormScreen({super.key});

  @override
  State<BeneficiaryCaseFormScreen> createState() =>
      _BeneficiaryCaseFormScreenState();
}

class _BeneficiaryCaseFormScreenState extends State<BeneficiaryCaseFormScreen> {
  final _title = TextEditingController();
  final _fullName = TextEditingController();
  final _nationalId = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _address = TextEditingController();
  final _familyCount = TextEditingController();
  final _income = TextEditingController();
  final _housing = TextEditingController();
  final _work = TextEditingController();
  final _health = TextEditingController();
  final _education = TextEditingController();
  final _needs = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _title.dispose();
    _fullName.dispose();
    _nationalId.dispose();
    _phone.dispose();
    _city.dispose();
    _district.dispose();
    _address.dispose();
    _familyCount.dispose();
    _income.dispose();
    _housing.dispose();
    _work.dispose();
    _health.dispose();
    _education.dispose();
    _needs.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_hasSignedInUser()) {
      Get.snackbar('Error'.tr, 'Please sign in again before submitting.'.tr);
      return;
    }

    final titleError = _requiredText(_title.text, 'Enter a public title.');
    final nameError = _requiredText(_fullName.text, 'Enter full name.');
    final phoneError = _requiredText(_phone.text, 'Enter phone.');
    final cityError = _requiredText(_city.text, 'Enter city.');
    final needsError = _requiredText(_needs.text, 'Enter actual needs.');
    final firstError =
        titleError ?? nameError ?? phoneError ?? cityError ?? needsError;
    if (firstError != null) {
      Get.snackbar('Error'.tr, firstError);
      return;
    }

    final familyCount = int.tryParse(_familyCount.text.trim());
    if (_familyCount.text.trim().isNotEmpty &&
        (familyCount == null || familyCount < 0)) {
      Get.snackbar('Error'.tr, 'Enter a valid family member count.'.tr);
      return;
    }

    final income = double.tryParse(_income.text.trim());
    if (_income.text.trim().isNotEmpty && (income == null || income < 0)) {
      Get.snackbar('Error'.tr, 'Enter a valid income amount.'.tr);
      return;
    }

    setState(() => _loading = true);
    try {
      await const ModuleApi().postJson(beneficiaryCasesUrl, {
        'user_id': sharedPreferences.getString('id_user') ?? '',
        'content_locale': currentContentLocaleTag(),
        'public_title': _title.text,
        'full_name': _fullName.text,
        'national_id': _nationalId.text,
        'phone': _phone.text,
        'city': _city.text,
        'district': _district.text,
        'address': _address.text,
        'family_members_count': familyCount,
        'income_amount': income,
        'housing_status': _housing.text,
        'work_status': _work.text,
        'health_status': _health.text,
        'education_status': _education.text,
        'actual_needs': _needs.text,
        'priority_level': 'medium',
      });
      if (!mounted) return;
      if (Get.isRegistered<MyBeneficiaryCasesController>()) {
        await Get.find<MyBeneficiaryCasesController>().fetchCases();
      }
      Get.back<void>();
      Get.snackbar('Submitted'.tr, 'Beneficiary case saved for review.'.tr);
    } catch (e) {
      if (mounted) Get.snackbar('Error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SimpleFormScaffold(
      title: 'Submit beneficiary case',
      subtitle: 'Private information is sent to the institution for review.',
      loading: _loading,
      submitLabel: 'Submit case',
      onSubmit: _submit,
      fields: [
        _ProposalTextField(controller: _title, label: 'Public title'),
        _ProposalTextField(controller: _fullName, label: 'Full name'),
        _ProposalTextField(controller: _nationalId, label: 'National ID'),
        _ProposalTextField(controller: _phone, label: 'Phone'),
        _ProposalTextField(controller: _city, label: 'City'),
        _ProposalTextField(controller: _district, label: 'District'),
        _ProposalTextField(controller: _address, label: 'Address', maxLines: 2),
        _ProposalTextField(
          controller: _familyCount,
          label: 'Family members',
          keyboardType: TextInputType.number,
        ),
        _ProposalTextField(
          controller: _income,
          label: 'Income amount',
          keyboardType: TextInputType.number,
        ),
        _ProposalTextField(controller: _housing, label: 'Housing status'),
        _ProposalTextField(controller: _work, label: 'Work status'),
        _ProposalTextField(
          controller: _health,
          label: 'Health status',
          maxLines: 3,
        ),
        _ProposalTextField(
          controller: _education,
          label: 'Education status',
          maxLines: 3,
        ),
        _ProposalTextField(
          controller: _needs,
          label: 'Actual needs',
          maxLines: 4,
        ),
      ],
    );
  }
}

class _SponsorshipFormScreenState extends State<SponsorshipFormScreen> {
  final _type = TextEditingController(text: 'General support');
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  late final FeaturedCampaignsController _campaignsController;
  int? _selectedCampaignId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _campaignsController = Get.isRegistered<FeaturedCampaignsController>()
        ? Get.find<FeaturedCampaignsController>()
        : Get.put(FeaturedCampaignsController());
  }

  @override
  void dispose() {
    _type.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _selectSponsorshipTarget(int? campaignId) {
    setState(() {
      _selectedCampaignId = campaignId;
      _type.text = campaignId == null ? 'General support' : 'Campaign support';
    });
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      Get.snackbar('Error'.tr, 'Enter a valid monthly amount.'.tr);
      return;
    }
    setState(() => _loading = true);
    try {
      await const ModuleApi().postJson(sponsorshipsUrl, {
        'user_id': sharedPreferences.getString('id_user') ?? '',
        'sponsorship_type': _type.text,
        'project_request_id': _selectedCampaignId,
        'amount': amount,
        'currency': 'IQD',
        'schedule_interval': 'monthly',
        'notes': _notes.text,
      });
      if (!mounted) return;
      if (Get.isRegistered<SponsorshipsController>()) {
        await Get.find<SponsorshipsController>().fetchSponsorships();
      }
      if (Get.isRegistered<NotificationsController>()) {
        await Get.find<NotificationsController>().refreshNotifications();
      }
      Get.back<void>();
      Get.snackbar(
        'Submitted'.tr,
        'Sponsorship request saved for admin review.'.tr,
      );
    } catch (e) {
      if (mounted) Get.snackbar('Error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SimpleFormScaffold(
      title: 'Create sponsorship',
      subtitle: 'Register a recurring community support commitment.',
      loading: _loading,
      submitLabel: 'Save sponsorship',
      onSubmit: _submit,
      fields: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => Get.to(() => const SponsorshipOverviewScreen()),
            icon: const Icon(Icons.list_alt_rounded),
            label: Text('My sponsorships'.tr),
          ),
        ),
        _SponsorshipCampaignPicker(
          controller: _campaignsController,
          selectedCampaignId: _selectedCampaignId,
          onSelected: _selectSponsorshipTarget,
        ),
        _ProposalTextField(controller: _type, label: 'Sponsorship type'),
        _ProposalTextField(controller: _amount, label: 'Monthly amount IQD'),
        _ProposalTextField(controller: _notes, label: 'Notes', maxLines: 3),
      ],
    );
  }
}

class _SponsorshipCampaignPicker extends StatelessWidget {
  const _SponsorshipCampaignPicker({
    required this.controller,
    required this.selectedCampaignId,
    required this.onSelected,
  });

  final FeaturedCampaignsController controller;
  final int? selectedCampaignId;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final campaigns = controller.campaigns;
      final selected = campaigns.where((c) => c.id == selectedCampaignId);
      final dropdownValue = selectedCampaignId == null || selected.isNotEmpty
          ? selectedCampaignId
          : null;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int?>(
            value: dropdownValue,
            decoration: InputDecoration(
              labelText: 'Sponsorship target'.tr,
              helperText:
                  'Choose general support or connect this monthly sponsorship to a campaign.'
                      .tr,
            ),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text('General support'.tr),
              ),
              ...campaigns.map(
                (FeaturedCampaignData campaign) => DropdownMenuItem<int?>(
                  value: campaign.id,
                  child: Text(campaign.title, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: onSelected,
          ),
          if (controller.isLoading.value)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(),
            ),
          if (controller.errorMessage.value != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextButton.icon(
                onPressed: controller.refreshCampaigns,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('Campaigns could not load. Tap to retry.'.tr),
              ),
            ),
        ],
      );
    });
  }
}

class InKindDonationFormScreen extends StatefulWidget {
  const InKindDonationFormScreen({super.key});

  @override
  State<InKindDonationFormScreen> createState() =>
      _InKindDonationFormScreenState();
}

class _InKindDonationFormScreenState extends State<InKindDonationFormScreen> {
  final _category = TextEditingController(text: 'Food');
  final _item = TextEditingController();
  final _quantity = TextEditingController();
  final _address = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _category.dispose();
    _item.dispose();
    _quantity.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await const ModuleApi().postJson(inKindDonationsUrl, {
        'user_id': sharedPreferences.getString('id_user') ?? '',
        'category': _category.text,
        'item_name': _item.text,
        'quantity': _quantity.text,
        'pickup_address': _address.text,
      });
      if (!mounted) return;
      Get.back<void>();
      Get.snackbar('Submitted'.tr, 'In-kind donation saved.'.tr);
    } catch (e) {
      if (mounted) Get.snackbar('Error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SimpleFormScaffold(
      title: 'In-kind donation',
      subtitle: 'Submit items for institution review and delivery.',
      loading: _loading,
      submitLabel: 'Submit donation',
      onSubmit: _submit,
      fields: [
        _ProposalTextField(controller: _category, label: 'Category'),
        _ProposalTextField(controller: _item, label: 'Item name'),
        _ProposalTextField(controller: _quantity, label: 'Quantity'),
        _ProposalTextField(controller: _address, label: 'Pickup address'),
      ],
    );
  }
}

class MarriageProfileFormScreen extends StatefulWidget {
  const MarriageProfileFormScreen({super.key});

  @override
  State<MarriageProfileFormScreen> createState() =>
      _MarriageProfileFormScreenState();
}

class _MarriageProfileFormScreenState extends State<MarriageProfileFormScreen> {
  final _gender = TextEditingController();
  final _age = TextEditingController();
  final _city = TextEditingController();
  final _summary = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _gender.text = sharedPreferences.getString('gender_user')?.trim() ?? '';
  }

  @override
  void dispose() {
    _gender.dispose();
    _age.dispose();
    _city.dispose();
    _summary.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await const ModuleApi().postJson(marriageProfilesUrl, {
        'user_id': sharedPreferences.getString('id_user') ?? '',
        'gender': _gender.text.trim(),
        'age': _age.text,
        'city': _city.text,
        'social_summary': _summary.text,
      });
      if (!mounted) return;
      if (Get.isRegistered<NotificationsController>()) {
        await Get.find<NotificationsController>().refreshNotifications();
      }
      Get.back<void>();
      Get.snackbar('Submitted'.tr, 'Marriage service profile saved.'.tr);
    } catch (e) {
      if (mounted) Get.snackbar('Error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SectionScaffold(
        title: 'Marriage service',
        subtitle: 'Private request reviewed by the institution.',
        child: Column(
          children: [
            const _MarriageHero(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: _SegmentedTabs(tabs: ['Marriage posts'.tr, 'Request'.tr]),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const _MarriageMediaTab(),
                  _buildRequestTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        GlassPanel(
          child: Column(
            children: [
              _ProposalTextField(controller: _gender, label: 'Gender'),
              const SizedBox(height: 14),
              _ProposalTextField(controller: _age, label: 'Age'),
              const SizedBox(height: 14),
              _ProposalTextField(controller: _city, label: 'City'),
              const SizedBox(height: 14),
              _ProposalTextField(
                controller: _summary,
                label: 'Social summary',
                maxLines: 4,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('Submit profile'.tr),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Marriage-specific media feed (post_type='marriage'), shown as the second
/// tab of the Marriage service screen. Visible to every role.
class _MarriageMediaTab extends StatefulWidget {
  const _MarriageMediaTab();

  @override
  State<_MarriageMediaTab> createState() => _MarriageMediaTabState();
}

class _MarriageMediaTabState extends State<_MarriageMediaTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = const ModuleApi().mediaPostsByType('marriage');
  }

  Future<void> _refresh() async {
    setState(() {
      _future = const ModuleApi().mediaPostsByType('marriage');
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data ?? const <Map<String, dynamic>>[];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              if (snapshot.hasError)
                SectionTile(
                  icon: Icons.diversity_1_rounded,
                  title: 'Marriage posts',
                  subtitle: 'Could not load posts. Pull to retry.',
                  color: Colors.deepPurple,
                  onTap: _refresh,
                )
              else if (items.isEmpty)
                const SectionTile(
                  icon: Icons.diversity_1_rounded,
                  title: 'Marriage posts',
                  subtitle: 'No marriage posts have been published yet.',
                  color: Colors.deepPurple,
                )
              else
                for (final item in items) ...[
                  MediaPostCard(item: item),
                  const SizedBox(height: 14),
                ],
            ],
          ),
        );
      },
    );
  }
}

/// Decorative gradient banner at the top of the Marriage service screen.
class _MarriageHero extends StatelessWidget {
  const _MarriageHero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.30),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Marriage service'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Programs, stories, and private requests.'.tr,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill-style segmented control wrapping a [TabBar] (must sit under a
/// DefaultTabController). `tabs` are already-localized labels.
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.tabs});

  final List<String> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeConfig.border(context)),
      ),
      child: TabBar(
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(colors: AppThemeConfig.heroGradient),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(10),
        labelColor: Colors.white,
        unselectedLabelColor: AppThemeConfig.mutedText(context),
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        tabs: [for (final t in tabs) Tab(text: t)],
      ),
    );
  }
}

class SupportTicketFormScreen extends StatefulWidget {
  const SupportTicketFormScreen({super.key});

  @override
  State<SupportTicketFormScreen> createState() =>
      _SupportTicketFormScreenState();
}

class _SupportTicketFormScreenState extends State<SupportTicketFormScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await const ModuleApi().postJson(supportTicketsUrl, {
        'user_id': sharedPreferences.getString('id_user') ?? '',
        'subject': _subject.text,
        'message': _message.text,
      });
      if (!mounted) return;
      Get.back<void>();
      Get.snackbar('Submitted'.tr, 'Support ticket saved.'.tr);
    } catch (e) {
      if (mounted) Get.snackbar('Error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SimpleFormScaffold(
      title: 'Technical support',
      subtitle: 'Send a message to the support team.',
      loading: _loading,
      submitLabel: 'Send request',
      onSubmit: _submit,
      fields: [
        _ProposalTextField(controller: _subject, label: 'Subject'),
        _ProposalTextField(controller: _message, label: 'Message', maxLines: 5),
      ],
    );
  }
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Reports',
      subtitle: 'Platform impact and financial overview.',
      child: FutureBuilder<Map<String, dynamic>>(
        future: const ModuleApi().reports(),
        builder: (context, snapshot) {
          final data = snapshot.data ?? const <String, dynamic>{};
          final donations = data['donations'] is Map
              ? Map<String, dynamic>.from(data['donations'] as Map)
              : <String, dynamic>{};
          final volunteers = data['volunteers'] is Map
              ? Map<String, dynamic>.from(data['volunteers'] as Map)
              : <String, dynamic>{};
          final isVolunteer = sharedPreferences.getString('role_id') == '3';
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator()),
              if (snapshot.hasError)
                const SectionTile(
                  icon: Icons.query_stats_rounded,
                  title: 'Reports',
                  subtitle: 'Unable to load reports from the server.',
                  color: Colors.cyan,
                ),
              if (!snapshot.hasError &&
                  snapshot.connectionState != ConnectionState.waiting) ...[
                if (isVolunteer) ...[
                  SectionTile(
                    icon: Icons.assignment_turned_in_rounded,
                    title: 'Open volunteer missions',
                    subtitle: '@count available now'.trParams({
                      'count': '${volunteers['missions_open'] ?? '0'}',
                    }),
                    color: Colors.green,
                  ),
                  const SizedBox(height: 12),
                  SectionTile(
                    icon: Icons.pending_actions_rounded,
                    title: 'Pending mission signups',
                    subtitle: '@count waiting for admin review'.trParams({
                      'count': '${volunteers['signups_pending'] ?? '0'}',
                    }),
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 12),
                  SectionTile(
                    icon: Icons.fact_check_rounded,
                    title: 'Attendance recorded',
                    subtitle: '@count attended signups'.trParams({
                      'count': '${volunteers['attended_total'] ?? '0'}',
                    }),
                    color: Colors.indigo,
                  ),
                  const SizedBox(height: 12),
                  SectionTile(
                    icon: Icons.verified_rounded,
                    title: 'Completed volunteer work',
                    subtitle: '@count completed signups, @hours hours'
                        .trParams({
                          'count': '${volunteers['signups_completed'] ?? '0'}',
                          'hours': '${volunteers['hours_served'] ?? '0'}',
                        }),
                    color: Colors.pinkAccent,
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  SectionTile(
                    icon: Icons.payments_rounded,
                    title: 'Completed donations',
                    subtitle: '${donations['completed_amount'] ?? '0'} IQD',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 12),
                  SectionTile(
                    icon: Icons.hourglass_bottom_rounded,
                    title: 'Pending donations',
                    subtitle: '${donations['pending_amount'] ?? '0'} IQD',
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 12),
                ],
                SectionTile(
                  icon: Icons.assignment_turned_in_rounded,
                  title: 'Project request groups',
                  subtitle:
                      '${(data['project_requests'] as List?)?.length ?? 0} status groups',
                  color: Colors.indigo,
                ),
                const SizedBox(height: 12),
                SectionTile(
                  icon: Icons.receipt_long_rounded,
                  title: 'Expense groups',
                  subtitle:
                      '${(data['expenses'] as List?)?.length ?? 0} expense groups',
                  color: Colors.pinkAccent,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SimpleFormScaffold extends StatelessWidget {
  const _SimpleFormScaffold({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.loading,
    required this.submitLabel,
    required this.onSubmit,
  });

  final String title;
  final String subtitle;
  final List<Widget> fields;
  final bool loading;
  final String submitLabel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: title,
      subtitle: subtitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          GlassPanel(
            child: Column(
              children: [
                ...fields.expand(
                  (field) => [field, const SizedBox(height: 14)],
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : onSubmit,
                    child: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(submitLabel.tr),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposalTextField extends StatelessWidget {
  const _ProposalTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label.tr),
    );
  }
}
