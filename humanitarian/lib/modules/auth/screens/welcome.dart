import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../localization/locale_service.dart';
import '../../../widgets/auth_ui.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

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
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _LanguageSelector(),
            ),
            const SizedBox(height: 20),
            Center(
              child: AuthBadge(
                icon: Icons.volunteer_activism_rounded,
                label: 'Humanitarian platform'.tr,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              height: 88,
              width: 88,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              // BalanceNex brand mark, clipped to the circular badge.
              child: ClipOval(
                child: Image.asset(
                  'assets/branding/balancenex_icon.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Build impact with a calmer, smarter experience.'.tr,
              style: titleStyle,
            ),
            const SizedBox(height: 12),
            Text(
              'Empower communities, coordinate your work, and keep every important step in one beautiful place.'
                  .tr,
              style: subtitleStyle,
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: const [
                AuthFeatureChip(
                  icon: Icons.groups_rounded,
                  label: 'Community-first',
                ),
                AuthFeatureChip(
                  icon: Icons.track_changes_rounded,
                  label: 'Track progress',
                ),
                AuthFeatureChip(
                  icon: Icons.bolt_rounded,
                  label: 'Fast onboarding',
                ),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Get.offAllNamed('/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0B385D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  elevation: 0,
                ),
                child: Text('Sign in'.tr),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Get.toNamed('/register'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.34)),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text('Create account'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector();

  @override
  Widget build(BuildContext context) {
    // #38 — pick the app language from a dropdown.
    final options = <(String, Locale)>[
      ('English', AppLocaleService.english),
      ('Arabic', AppLocaleService.arabic),
      ('Kurdish Sorani', AppLocaleService.kurdishSorani),
      ('Kurdish Badini', AppLocaleService.kurdishBadini),
    ];
    final currentCode = AppLocaleService.localeTag(
      Get.locale ?? AppLocaleService.english,
    );
    final current = options
        .firstWhere(
          (o) => AppLocaleService.localeTag(o.$2) == currentCode,
          orElse: () => options.first,
        )
        .$2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Language'.tr,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0B385D).withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Locale>(
              value: current,
              isDense: true,
              dropdownColor: const Color(0xFF0B385D),
              iconEnabledColor: Colors.white,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              items: [
                for (final o in options)
                  DropdownMenuItem<Locale>(value: o.$2, child: Text(o.$1.tr)),
              ],
              onChanged: (loc) {
                if (loc != null) AppLocaleService.changeLocale(loc);
              },
            ),
          ),
        ),
      ],
    );
  }
}
