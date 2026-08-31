import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';

import '../../../localization/locale_service.dart';
import '../../../widgets/auth_ui.dart';

/// The very first screen the app shows, before sign-in.
///
/// REDESIGN RATIONALE (apple-design skill: Purpose, Simplicity-not-minimalism,
/// Craft; ui-ux-pro-max: onboarding/welcome pattern guidance — mobile-first,
/// one clear call to action).
///
/// The previous layout put every element inside `AuthGlassCard` — the same
/// bordered/shadowed panel used for the phone-number *form* on Login. A
/// first-run screen with a single action is not a form, so wrapping it in
/// form chrome (Craft: "nothing is random — every choice is deliberate")
/// made a one-tap screen look like it required filling something in, and
/// centring that small card left large empty bands above and below it with
/// no purpose (Simplicity: "burying everything in one place looks minimal
/// but isn't simple" — the emptiness here wasn't a choice, it was leftover
/// space).
///
/// This version removes the card and paints the three ideas — brand,
/// promise, action — directly on the page in one continuous vertical
/// rhythm, in the order a first-time visitor actually needs them:
///   1. Brand mark, given real presence (a soft tonal backdrop, not a small
///      circle in a box) — Purpose: a first-run screen's job is to say what
///      this is before it asks for anything.
///   2. The promise (badge + heading) — hierarchy built from weight + size
///      + leading together, per the size-specific typography guidance:
///      the heading is large and tight (negative-ish leading, heavier
///      weight), not just "the same style, bigger."
///   3. One primary action and the sentence explaining what it does.
/// The language control moves out of the card into its own top bar row —
/// a considered home instead of an orphaned pill — and keeps the exact
/// same `PopupMenuButton` implementation from #38 (glass-pill trigger, its
/// own rounded popup), only relocated.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Large display heading: apple-design's size-specific tracking rule —
    // tighten large text, loosen leading is not needed here since it's
    // short (max 2 lines), but tight line-height keeps a 2-line heading
    // from reading as two disconnected sentences.
    final headingStyle = Theme.of(context).textTheme.headlineLarge?.copyWith(
      color: AppThemeConfig.text(context),
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: -0.3,
    );

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top bar: language control's considered home ────────────────
          // A real bar, not a pill floating loose above the card. Kept at
          // the physical trailing edge per #38 (Align uses centerEnd, which
          // is directional and correctly flips for RTL).
          const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _LanguageSelector(),
          ),
          const SizedBox(height: 32),
          // ── Brand: presence appropriate to a first-run screen ──────────
          const Center(child: _BrandMark()),
          const SizedBox(height: 24),
          Center(
            child: AuthBadge(
              icon: Icons.volunteer_activism_rounded,
              label: 'Humanitarian platform',
            ),
          ),
          const SizedBox(height: 16),
          // #38 — approved verbal identity: short heading, no tagline.
          Text(
            'Balance and Stability for a Better Life!'.tr,
            textAlign: TextAlign.center,
            style: headingStyle,
          ),
          // Deliberate breathing room between the promise and the action —
          // large enough to read as a section break, not leftover space.
          const SizedBox(height: 40),
          // ── Action ───────────────────────────────────────────────────
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
          ElevatedButton(
            // #39 — push, not offAllNamed, so Login keeps a back target.
            onPressed: () => Get.toNamed('/login'),
            style: ElevatedButton.styleFrom(
              // Prefer the theme-adaptive accent over the deprecated
              // constant `primary` (fixed colour, doesn't shift with
              // brightness) — see AppThemeConfig's own migration note.
              // `accent`/`onAccent` are the pair measured >=4.5:1 in both
              // themes (6.87:1 / 8.33:1 light-dark for the fill; 7.54:1 /
              // 7.72:1 for the text on it).
              backgroundColor: AppThemeConfig.accent(context),
              foregroundColor: AppThemeConfig.onAccent(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(vertical: 18),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              elevation: 0,
              minimumSize: const Size.fromHeight(52), // clears the 44pt target
            ),
            child: Text('Continue with phone'.tr),
          ),
          const SizedBox(height: 12),
          // Says out loud what the single button covers, so a returning
          // user isn't left wondering where "Sign in" went.
          Text(
            'Sign in or create an account with your phone number.'.tr,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppThemeConfig.mutedText(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// The BalanceNex brand mark, given real weight for a first-run screen: a
/// soft tonal backdrop (the accent's own wash tint — Craft: "colours that
/// adapt to light/dark") sitting behind a larger circular logo, instead of
/// the previous small 88px circle boxed inside a card. Materials guidance
/// (apple-design §12): a tonal fill used with intent to give the mark
/// presence, not a translucent effect for its own sake.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final wash = AppColors.of(context).accentWash;
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Decorative backdrop only — never intercepts taps, and carries
          // no text, so it needs no contrast check of its own.
          IgnorePointer(
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
            ),
          ),
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              color: AppThemeConfig.border(context),
              shape: BoxShape.circle,
              border: Border.all(color: AppThemeConfig.border(context)),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/branding/balancenex_icon.png',
                width: 116,
                height: 116,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
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
/// card style and looked out of place. Relocated (this redesign) from an
/// orphaned position inside the card into the screen's own top bar; the
/// trigger and menu implementation are unchanged.
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
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
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
