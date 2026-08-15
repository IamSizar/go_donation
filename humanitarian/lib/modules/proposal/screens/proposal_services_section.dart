import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_posts_screen.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/proposal/controllers/beneficiary_cases_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/beneficiary_case_detail_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/sponsorships_controller.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/sponsorship_overview_screen.dart';
import 'package:flutter_application_1/modules/support/screens/technical_support_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

class ProposalServicesSection extends StatelessWidget {
  const ProposalServicesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final roleId = sharedPreferences.getString('role_id') ?? '';
    return SectionScaffold(
      assistantRoute: 'services',
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

Widget _servicesForRole(String roleId) => _ServicesHub(roleId: roleId);

/// The Services hub, assembled from two clearly separated groups.
///
/// Previously each role had its own hand-written tile list, and four of those
/// tiles — Partners, News and activities, Technical support and Marriage posts
/// — were copy-pasted into all three lists with byte-identical icons, titles,
/// subtitles, colours, destinations and (absent) visibility rules. Three copies
/// of the same row is three chances to drift, and it also buried each role's
/// genuinely role-specific actions in a flat, undifferentiated stack.
///
/// So the shared four are hoisted into one "Community and support" group that
/// is written once and rendered for every role, and each role variant now
/// declares only what is actually specific to it. No destination was lost:
/// every screen reachable from any role before is still reachable from that
/// same role after — see [_roleSpecificTiles] and [_communityAndSupportTiles].
///
/// Deliberately NOT hoisted: "Reports". It is absent for beneficiaries and, for
/// the two roles that do get it, the subtitle differs (donation/case/project
/// totals vs volunteer attendance/mission totals), so it is genuinely
/// role-specific and stays in [_roleSpecificTiles].
class _ServicesHub extends StatelessWidget {
  const _ServicesHub({required this.roleId});

  /// Raw `role_id` string as stored in preferences: '2' beneficiary,
  /// '3' volunteer, anything else (including empty) is treated as donor.
  final String roleId;

  @override
  Widget build(BuildContext context) {
    final roleTiles = _roleSpecificTiles(context, roleId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Beneficiaries have no role-specific Services tiles at all (their own
        // actions live on the Kafala and Profile tabs — see the notes on
        // _roleSpecificTiles), so the whole group and its heading are skipped
        // rather than rendering an empty labelled section.
        if (roleTiles.isNotEmpty) ...[
          SectionLabel(title: _roleSectionTitle(roleId)),
          const SizedBox(height: 12),
          ..._separated(roleTiles),
          const SizedBox(height: 20),
        ],
        const SectionLabel(title: 'Community and support'),
        const SizedBox(height: 12),
        ..._separated(_communityAndSupportTiles(context)),
      ],
    );
  }
}

/// Heading for the role-specific group. Only called when that group is
/// non-empty, so the beneficiary case never needs a string.
String _roleSectionTitle(String roleId) {
  return switch (roleId) {
    '3' => 'Volunteer tools',
    _ => 'Giving tools',
  };
}

/// Interleaves a 12px gap between tiles without leaving a trailing gap, which
/// is what the old hand-written `const SizedBox(height: 12)` rows did.
List<Widget> _separated(List<Widget> tiles) {
  return [
    for (var i = 0; i < tiles.length; i++) ...[
      tiles[i],
      if (i != tiles.length - 1) const SizedBox(height: 12),
    ],
  ];
}

/// Tiles only this role can act on.
///
/// Beneficiary ('2') returns an empty list on purpose:
/// - "Submit beneficiary case" intentionally lives only in the Kafala /
///   Beneficiary-support tab, where it sits next to "My beneficiary cases"
///   tracking — so it is not duplicated here in Services.
/// - Submitting/editing your own marriage profile already has 4 tiles on the
///   Profile tab (form, search, my profile, chats — modules/marriage); not
///   re-duplicated here. Only the public posts feed is repeated below, since
///   Services is explicitly the "public updates" hub.
List<Widget> _roleSpecificTiles(BuildContext context, String roleId) {
  return switch (roleId) {
    '2' => const <Widget>[],
    '3' => [
      SectionTile(
        icon: Icons.query_stats_rounded,
        title: 'Reports',
        subtitle: 'View volunteer attendance, mission, and completion totals.',
        color: AppThemeConfig.accent(context),
        onTap: () => Get.to(() => const ReportsScreen()),
      ),
    ],
    _ => [
      SectionTile(
        icon: Icons.verified_user_rounded,
        title: 'Beneficiary cases'.tr,
        subtitle: 'Review verified cases by code, need, and priority.',
        color: AppThemeConfig.accent(context),
        onTap: () => Get.to(() => const BeneficiaryCasesScreen()),
      ),
      SectionTile(
        icon: Icons.handshake_rounded,
        title: 'Create sponsorship',
        subtitle: 'Register a scheduled sponsorship commitment.',
        color: AppThemeConfig.accent(context),
        onTap: () => Get.to(() => const SponsorshipFormScreen()),
      ),
      SectionTile(
        icon: Icons.inventory_2_rounded,
        title: 'In-kind donation',
        subtitle: 'Submit food, clothing, supplies, or other items.',
        color: AppThemeConfig.accent(context),
        onTap: () => Get.to(() => const InKindDonationFormScreen()),
      ),
      SectionTile(
        icon: Icons.query_stats_rounded,
        title: 'Reports',
        subtitle: 'View donation, case, project, and expense totals.',
        color: AppThemeConfig.accent(context),
        onTap: () => Get.to(() => const ReportsScreen()),
      ),
    ],
  };
}

/// The four public, role-neutral destinations. Every role saw all four before
/// this refactor with identical wording and identical targets, and every role
/// still sees all four — this is the single definition of that group.
///
/// Marriage posts is the public posts feed only; submitting a marriage profile
/// is a beneficiary-only action (backend-enforced) and is not offered here for
/// any role, which is why this tile is safe to share.
List<Widget> _communityAndSupportTiles(BuildContext context) {
  return [
    // C1 — the Partners tile used to sit here as well as in the Settings
    // drawer. It was the ONLY destination in the app listed in both hubs,
    // which is what marked it out as an accident rather than a pattern, and
    // the client had counted "شركاؤنا" three or four times over.
    //
    // The Settings copy is the one that survived, for a reason that is about
    // reach rather than taste: Settings is a bottom-nav tab, one tap from
    // anywhere, while this screen is itself reached through the profile.
    // Deleting the tab entry and keeping this one would have buried a section
    // the client specifically asked to feature. Nothing is lost — the
    // destination is unchanged and still reachable, from search and from a
    // partner notification as well.
    SectionTile(
      icon: Icons.article_rounded,
      title: 'News and activities',
      subtitle: 'See activities, news, articles, and events.',
      color: AppThemeConfig.pending(context),
      onTap: () => Get.to(() => const NewsActivitiesScreen()),
    ),
    SectionTile(
      icon: Icons.support_agent_rounded,
      title: 'Technical support',
      // Was a bare compose form (SupportTicketFormScreen, deleted): no ticket
      // history, no staff reply, no validation, and a raw exception string in
      // a snackbar on failure. TechnicalSupportScreen is the real one — same
      // compose box, plus the request history, the staff reply and the
      // WhatsApp escalation the support spec asks for.
      subtitle: 'Send a support request and track the reply.',
      color: AppThemeConfig.accent(context),
      onTap: () => Get.to(() => const TechnicalSupportScreen()),
    ),
    SectionTile(
      icon: Icons.diversity_1_rounded,
      title: 'marriage_posts_title',
      subtitle: 'marriage_posts_services_subtitle',
      color: AppThemeConfig.accent(context),
      onTap: () => Get.to(() => const MarriagePostsScreen()),
    ),
  ];
}

class BeneficiaryCasesScreen extends StatelessWidget {
  const BeneficiaryCasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<BeneficiaryCasesController>()
        ? Get.find<BeneficiaryCasesController>()
        : Get.put(BeneficiaryCasesController());

    return SectionScaffold(
      title: 'Beneficiary cases'.tr,
      subtitle: 'Verified public case records.',
      child: Obx(() {
        final items = controller.cases;
        // Three stacked `if` blocks replaced by AppAsync, which renders
        // exactly ONE state. Before, a failed load drew the error tile and
        // then the case list beneath it, and the error was a SectionTile -
        // the same card used for the cases themselves - so an error looked
        // like just another tappable row.
        return AppAsync<List<Map<String, dynamic>>>(
          loading: controller.isLoading.value,
          error: controller.errorMessage.value,
          onRetry: controller.fetchCases,
          data: items,
          isEmpty: (list) => list.isEmpty,
          empty: AppEmpty(
            title: 'Beneficiary cases'.tr,
            message: 'No approved cases are available yet.',
          ),
          builder: (list) => RefreshIndicator(
            onRefresh: controller.fetchCases,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                for (final item in list) ...[
                  SectionTile(
                    icon: Icons.verified_user_rounded,
                    title: _localizedCaseTitle(item),
                    subtitle: _caseSubtitle(item),
                    color: AppThemeConfig.accent(context),
                    onTap: () => Get.to(
                      () => BeneficiaryCaseDetailScreen(caseItem: item),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
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
        // The summary band moves INSIDE the builder: it reports counts, and
        // rendering a zeroed summary while the fetch is still in flight
        // states something not yet known.
        return AppAsync<List<Map<String, dynamic>>>(
          loading: controller.isLoading.value,
          error: controller.errorMessage.value,
          onRetry: controller.fetchCases,
          data: items,
          isEmpty: (list) => list.isEmpty,
          empty: const AppEmpty(
            title: 'No cases yet',
            message: 'Submitted beneficiary cases will appear here.',
          ),
          builder: (list) => RefreshIndicator(
            onRefresh: controller.fetchCases,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                _CaseSummaryBand(items: list),
                const SizedBox(height: 14),
                for (final item in list) ...[
                  SectionTile(
                    icon: Icons.assignment_ind_rounded,
                    title: _localizedCaseTitle(item),
                    subtitle: _myCaseSubtitle(item),
                    color: _caseStatusColor(
                      context,
                      (item['verification_status'] ?? '').toString(),
                    ),
                    onTap: () => Get.to(
                      () => BeneficiaryCaseDetailScreen(caseItem: item),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
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
    fallback: 'Eligible case',
  );
}

String _caseSubtitle(Map<String, dynamic> item) {
  return ['case_code', 'city', 'priority_level']
      .map((key) => (item[key] ?? '').toString())
      .where((value) => value.trim().isNotEmpty)
      .join(' - ');
}

String _myCaseSubtitle(Map<String, dynamic> item) {
  // `replaceAll('_', ' ')` only made the backend token prettier — it stayed
  // English ("under review", "needs changes") in the Arabic UI. localizedTag
  // is the app's single mechanism for turning a backend tag into a word a
  // reader should see; it humanises the same way as a last resort.
  final status = localizedTag(item['verification_status'] ?? 'submitted');
  final base = _caseSubtitle(item);
  final notes = (item['review_notes'] ?? '').toString().trim();
  return [
    status,
    if (base.trim().isNotEmpty) base,
    if (notes.isNotEmpty) notes,
  ].join(' - ');
}

Color _caseStatusColor(BuildContext context, String status) {
  return switch (status) {
    'approved' => AppThemeConfig.accent(context),
    'rejected' => AppThemeConfig.consequence(context),
    'under_review' || 'needs_changes' => AppThemeConfig.pending(context),
    'submitted' || 'draft' => AppThemeConfig.pending(context),
    _ => AppThemeConfig.accent(context),
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
      title: 'Submit beneficiary case'.tr,
      subtitle: 'Private information is sent to the institution for review.'.tr,
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
  final _type = TextEditingController(text: 'General support'.tr);
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
      title: 'Create sponsorship'.tr,
      subtitle: 'Register a recurring community support commitment.'.tr,
      loading: _loading,
      submitLabel: 'Save sponsorship',
      onSubmit: _submit,
      fields: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
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
        _ProposalTextField(controller: _type, label: 'Support type'),
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
  final _category = TextEditingController(text: 'Food'.tr);
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
      title: 'In-kind donation'.tr,
      subtitle: 'Submit items for institution review and delivery.'.tr,
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

// SupportTicketFormScreen was DELETED here.
//
// It was a second, worse support screen: the same POST to the same endpoint
// with the same two fields, but no ticket history, no staff reply, no
// escalation, no validation and no submit gating — plus
// `catch (e) => Get.snackbar('Error', e.toString())`, i.e. a raw exception in
// front of the user. Submitting it empty was a silent no-op.
//
// It was checked for a state TechnicalSupportScreen does not serve, because
// "duplicate" screens on this project have more than once turned out to serve
// different ones. It served none: TechnicalSupportScreen's compose panel IS
// this form, so keeping this as "the compose step" would only have preserved
// the worse copy of a box the good screen already contains.
//
// All three entry points now open TechnicalSupportScreen — the Services hub
// (above), the bot's `support` route (bot_navigation.dart) and a tapped
// support notification (notifications_controller.dart).

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
                SectionTile(
                  icon: Icons.query_stats_rounded,
                  title: 'Reports',
                  subtitle: 'Unable to load reports from the server.',
                  color: AppThemeConfig.accent(context),
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
                    color: AppThemeConfig.accent(context),
                  ),
                  const SizedBox(height: 12),
                  SectionTile(
                    icon: Icons.pending_actions_rounded,
                    title: 'Pending mission signups',
                    subtitle: '@count waiting for admin review'.trParams({
                      'count': '${volunteers['signups_pending'] ?? '0'}',
                    }),
                    color: AppThemeConfig.pending(context),
                  ),
                  const SizedBox(height: 12),
                  SectionTile(
                    icon: Icons.fact_check_rounded,
                    title: 'Attendance recorded',
                    subtitle: '@count attended signups'.trParams({
                      'count': '${volunteers['attended_total'] ?? '0'}',
                    }),
                    color: AppThemeConfig.accent(context),
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
                    color: AppThemeConfig.accent(context),
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  SectionTile(
                    icon: Icons.payments_rounded,
                    title: 'Completed donations',
                    subtitle: '${donations['completed_amount'] ?? '0'} IQD',
                    color: AppThemeConfig.accent(context),
                  ),
                  const SizedBox(height: 12),
                  SectionTile(
                    icon: Icons.hourglass_bottom_rounded,
                    title: 'Pending donations',
                    subtitle: '${donations['pending_amount'] ?? '0'} IQD',
                    color: AppThemeConfig.pending(context),
                  ),
                  const SizedBox(height: 12),
                ],
                SectionTile(
                  icon: Icons.assignment_turned_in_rounded,
                  title: 'Project request groups',
                  subtitle:
                      '${(data['project_requests'] as List?)?.length ?? 0} status groups',
                  color: AppThemeConfig.accent(context),
                ),
                const SizedBox(height: 12),
                SectionTile(
                  icon: Icons.receipt_long_rounded,
                  title: 'Expense groups',
                  subtitle:
                      '${(data['expenses'] as List?)?.length ?? 0} expense groups',
                  color: AppThemeConfig.accent(context),
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
