import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class OrphanFamilyProfilesScreen extends StatelessWidget {
  const OrphanFamilyProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Orphan & Family Profiles',
      subtitle: 'See updates, family needs, and sponsorship history.',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: const [
          _ProfilesIntroCard(),
          SizedBox(height: 22),
          _ProfileCard(
            title: 'Amina',
            subtitle: 'Age 9 • Amman',
            note:
                'Recently started a new school term and needs transport support.',
            tag: 'Education priority',
            color: Colors.amber,
            icon: Icons.school_rounded,
          ),
          SizedBox(height: 14),
          _ProfileCard(
            title: 'Yousef Family',
            subtitle: 'Family of 5 • Zarqa',
            note:
                'Monthly sponsorship is helping with food packages and rent continuity.',
            tag: 'Stable support',
            color: Colors.teal,
            icon: Icons.family_restroom_rounded,
          ),
          SizedBox(height: 14),
          _ProfileCard(
            title: 'Mariam',
            subtitle: 'Age 12 • Irbid',
            note:
                'Shared a story update after receiving winter supplies and tutoring help.',
            tag: 'New update',
            color: Colors.blueAccent,
            icon: Icons.auto_stories_rounded,
          ),
        ],
      ),
    );
  }
}

class _ProfilesIntroCard extends StatelessWidget {
  const _ProfilesIntroCard();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profile directory'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Each profile gives donors a clearer understanding of who is being supported, what needs are active, and what progress has been shared recently.'
                .tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.title,
    required this.subtitle,
    required this.note,
    required this.tag,
    required this.color,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String note;
  final String tag;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TileIcon(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.tr,
                      style: TextStyle(
                        color: AppThemeConfig.text(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tag.tr,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            note.tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
