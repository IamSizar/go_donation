import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';

import '../../../localization/locale_service.dart';
import '../../../widgets/auth_ui.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      color: AppThemeConfig.text(context),
      fontWeight: FontWeight.w800,
      height: 1.1,
    );

    return AuthScaffold(
      child: AuthGlassCard(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // #38 — language switcher pinned to the physical right, regardless
            // of RTL locale (Alignment.centerRight, not centerEnd).
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _LanguageSelector(),
            ),
            const SizedBox(height: 20),
            Center(
              child: AuthBadge(
                icon: Icons.volunteer_activism_rounded,
                label: 'Humanitarian platform',
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Container(
                height: 88,
                width: 88,
                decoration: BoxDecoration(
                  color: AppThemeConfig.border(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppThemeConfig.border(context)),
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
            ),
            const SizedBox(height: 24),
            // #38 — approved verbal identity: short heading, no tagline.
            Text(
              'Balance and Stability for a Better Life!'.tr,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
            const SizedBox(height: 28),
            // One entry action, not two. This screen used to show a filled
            // "Sign in" button and an outlined "Create account" button, but
            // both navigated to '/login' — the outlined one only existed
            // because a dedicated email/password RegisterPage was planned.
            // That page never called an API (it faked a delay and jumped to
            // '/verify'), so it was deleted; the phone/OTP flow on Login is
            // the single path that both signs in existing users and registers
            // new ones. Two buttons for one destination was a false choice,
            // so the copy names the mechanism ("Continue with phone") instead
            // of picking a side — "Sign in" would under-describe it and
            // "Create account" would mislead returning users.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // #39 — push, not offAllNamed, so Login keeps a back target.
                onPressed: () => Get.toNamed('/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemeConfig.primary,
                  foregroundColor: Colors.white,
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
                child: Text('Continue with phone'.tr),
              ),
            ),
            const SizedBox(height: 12),
            // Says out loud what the single button covers, so a returning
            // user isn't left wondering where "Sign in" went.
            // Full-width box because the Column is start-aligned, so a bare
            // Text would shrink-wrap and textAlign.center would do nothing.
            SizedBox(
              width: double.infinity,
              child: Text(
                'Sign in or create an account with your phone number.'.tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppThemeConfig.mutedText(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangOption {
  const _LangOption(this.code, this.name, this.locale);
  final String code;
  final String name;
  final Locale locale;
}

/// #38 — redesigned language switcher: a compact glass pill (matches
/// AuthBadge's visual language) that opens a rounded popup menu instead of
/// the plain native DropdownButton box, which clashed with the frosted-glass
/// card style and looked out of place.
class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector();

  static const _options = <_LangOption>[
    _LangOption('EN', 'English', AppLocaleService.english),
    _LangOption('AR', 'Arabic', AppLocaleService.arabic),
    _LangOption('CKB', 'Kurdish Sorani', AppLocaleService.kurdishSorani),
    _LangOption('BAD', 'Kurdish Badini', AppLocaleService.kurdishBadini),
  ];

  @override
  Widget build(BuildContext context) {
    final currentCode = AppLocaleService.localeTag(
      Get.locale ?? AppLocaleService.english,
    );
    final current = _options.firstWhere(
      (o) => AppLocaleService.localeTag(o.locale) == currentCode,
      orElse: () => _options.first,
    );

    return PopupMenuButton<_LangOption>(
      initialValue: current,
      offset: const Offset(0, 46),
      color: const Color(0xFF0E3B5C),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppThemeConfig.border(context)),
      ),
      onSelected: (o) => AppLocaleService.changeLocale(o.locale),
      itemBuilder: (context) => [
        for (final o in _options)
          PopupMenuItem<_LangOption>(
            value: o,
            child: Row(
              children: [
                _LangCodeBadge(code: o.code, selected: o == current),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    o.name.tr,
                    style: TextStyle(
                      color: AppThemeConfig.text(context),
                      fontWeight: o == current
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (o == current)
                  Icon(
                    Icons.check_rounded,
                    color: AppThemeConfig.text(context),
                    size: 18,
                  ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppThemeConfig.surface(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppThemeConfig.border(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language_rounded,
              size: 18,
              color: AppThemeConfig.text(context),
            ),
            const SizedBox(width: 8),
            Text(
              current.code,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: AppThemeConfig.mutedText(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small circular code badge shown beside each option in the popup menu.
class _LangCodeBadge extends StatelessWidget {
  const _LangCodeBadge({required this.code, required this.selected});

  final String code;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? AppThemeConfig.border(context)
            : AppThemeConfig.border(context),
        shape: BoxShape.circle,
        border: Border.all(color: AppThemeConfig.border(context)),
      ),
      child: Text(
        code,
        style: TextStyle(
          color: AppThemeConfig.text(context),
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}
