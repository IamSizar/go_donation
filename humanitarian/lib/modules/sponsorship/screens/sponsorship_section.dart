import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_campaign_donations_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_my_projects_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_pending_projects_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_submit_project_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/orphan_family_profiles_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/sponsorship_overview_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class SponsorshipSection extends StatelessWidget {
  const SponsorshipSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isBeneficiary = sharedPreferences.getString('role_id') == '2';
    return SectionScaffold(
      title: isBeneficiary ? 'Beneficiary support' : 'Kafala Sponsorship',
      subtitle: isBeneficiary
          ? 'Submit help requests and track admin review in one place.'
          : 'Monitor sponsorship plans, your submitted projects, and stories.',
      child: isBeneficiary
          ? const _BeneficiarySupportList()
          : const _SponsorshipList(),
    );
  }
}

class _BeneficiarySupportList extends StatelessWidget {
  const _BeneficiarySupportList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  InfoChip(
                    icon: Icons.fact_check_rounded,
                    label: 'Admin review',
                  ),
                  InfoChip(
                    icon: Icons.notifications_active_rounded,
                    label: 'Status alerts',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Your beneficiary workspace'.tr,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create assistance requests, follow approval status, and contact support without donor-only tools in the way.'
                    .tr,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.upload_file_rounded,
          title: 'Submit project for help',
          subtitle: 'Send a project request with budget, location, and needs.',
          color: Colors.deepPurple,
          onTap: () => Get.to(() => const BeneficiarySubmitProjectScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.volunteer_activism_rounded,
          title: 'My campaign donations',
          subtitle: 'See every donation made to your campaigns and who donated.',
          color: Colors.teal,
          onTap: () => Get.to(
            () => const BeneficiaryCampaignDonationsScreen(),
          ),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.dashboard_customize_rounded,
          title: 'My help requests',
          subtitle: 'See submitted, pending, approved, and rejected requests.',
          color: Colors.indigo,
          onTap: () => Get.to(() => const BeneficiaryMyProjectsScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.pending_actions_rounded,
          title: 'Pending projects for help',
          subtitle: 'Review requests still waiting for action or matching.',
          color: Colors.amber,
          onTap: () => Get.to(() => const BeneficiaryPendingProjectsScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.assignment_ind_rounded,
          title: 'Submit beneficiary case',
          subtitle: 'Send family, income, housing, and needs information.',
          color: Colors.green,
          onTap: () => Get.to(() => const BeneficiaryCaseFormScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.fact_check_rounded,
          title: 'My beneficiary cases',
          subtitle: 'Track submitted, reviewed, approved, and rejected cases.',
          color: Colors.teal,
          onTap: () => Get.to(() => const MyBeneficiaryCasesScreen()),
        ),
        // Technical support intentionally lives only in the Services tab (it is
        // the shared support entry point for every role), so it is not
        // duplicated here in the beneficiary workspace.
      ],
    );
  }
}

class _SponsorshipList extends StatelessWidget {
  const _SponsorshipList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        SectionTile(
          icon: Icons.family_restroom_rounded,
          title: 'Overview',
          subtitle: 'Review current sponsorship activity and milestones.',
          color: Colors.teal,
          onTap: () => Get.to(() => const SponsorshipOverviewScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.handshake_rounded,
          title: 'Create monthly sponsorship',
          subtitle:
              'Choose general support or a campaign and submit it for admin review.',
          color: Colors.pinkAccent,
          onTap: () => Get.to(() => const SponsorshipFormScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.child_care_rounded,
          title: 'Orphan & Family Profiles',
          subtitle: 'See updates, family needs, and sponsorship history.',
          color: Colors.amber,
          onTap: () => Get.to(() => const OrphanFamilyProfilesScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.upload_file_rounded,
          title: 'Submit project for help',
          subtitle:
              'Propose a new initiative (e.g. water for all): title, budget, details.',
          color: Colors.deepPurple,
          onTap: () => Get.to(() => const BeneficiarySubmitProjectScreen()),
        ),
        const SizedBox(height: 12),
        SectionTile(
          icon: Icons.dashboard_customize_rounded,
          title: 'My projects',
          subtitle:
              'See each request’s status (pending, success, or failed), who liked it, and comments.',
          color: Colors.indigo,
          onTap: () => Get.to(() => const BeneficiaryMyProjectsScreen()),
        ),
      ],
    );
  }
}
