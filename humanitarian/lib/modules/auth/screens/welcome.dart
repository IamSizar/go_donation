import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';

import '../../../localization/locale_service.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/glass_ui.dart';

/// The very first screen the app shows, before sign-in.
///
/// SECOND-PASS RATIONALE (chunk 12 — the first redesign centred the whole
/// block and that was the bug, not a finished layout).
///
/// A real device screenshot (Motorola Defy, 720x1600, English/LTR) measured
/// four defects the first pass didn't fix, all rooted in the same cause:
/// wrapping everything in `AuthScaffold`, whose `Center` + `SingleChildScrollView`
/// treats a first-run screen like a form dialog — sized to its content and
/// centred in whatever space is left. That produced ~350px of dead space
/// above the header and ~300px below the subtitle (nothing anchored to
/// anything), a language pill floating alone ~350px down instead of living
/// in a header, and a heading whose size dominated the screen instead of
/// sitting below the brand in hierarchy.
///
/// This version stops delegating to `AuthScaffold` (which is still right
/// for the login/register forms it was built for) and lays the screen out
/// itself with three pinned regions instead of one centred block:
///   1. A top header (language control), pinned under the safe area.
///   2. A middle block (brand + promise) that scrolls internally if a large
///      Dynamic Type scale can't fit it, instead of pushing the CTA off
///      screen or letting the whole page overflow.
///   3. A bottom-pinned action (button + supporting line), anchored in
///      thumb reach above the safe-area/gesture-bar inset — not centred.
/// Deliberate empty space is left *between* the middle and bottom blocks
/// (an `Expanded` in the outer Column), so on a tall screen it reads as
/// breathing room between "what this is" and "what to do", not as slack
/// nobody accounted for.
///
/// Every region shares exactly one horizontal gutter (`_gutter`) — the
/// header, heading, button and subtitle all start at the same logical
/// (start/end) edge, fixing the two-different-insets defect. The heading
/// is also now left/start-aligned rather than centred: centred short text
/// inside a full-width container is what produced the illusion of a
/// narrower inset than the full-width button sitting beside it.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  /// The single horizontal inset shared by every piece of content on this
  /// screen (header, heading, button, subtitle) — on the 4/8/12/16/24/32
  /// spacing scale. Picking one value and applying it once, at the outer
  /// edge of each pinned region, is what guarantees defect 2 (two
  /// different gutters) can't recur: there is nowhere else a second inset
  /// could be introduced.
  static const double _gutter = 24;

  @override
  Widget build(BuildContext context) {
    // Reduced relative to the first pass: the heading now sits below the
    // brand in hierarchy instead of dominating the screen (titleLarge, not
    // headlineLarge). Large display text still wants slightly negative
    // tracking; body-sized text (the subtitle) is left near 0 untouched.
    final headingStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
      color: AppThemeConfig.text(context),
      fontWeight: FontWeight.w800,
      height: 1.15,
      letterSpacing: -0.2,
    );

    // Owner: the logo must sit at EXACTLY the same spot as on the launch
    // screen (native + routing splash draw it at the centre of the whole
    // screen), so the hand-over is seamless. The mark is therefore centred
    // on the full screen here too, independent of the header and button;
    // the tagline hangs a fixed distance below it.
    return GradientScreen(
      child: Stack(
        children: [
          const Center(child: BrandLogo()),
          LayoutBuilder(
            builder: (context, constraints) => Padding(
              padding: EdgeInsets.only(
                top: constraints.maxHeight / 2 + BrandLogo.ring / 2 + 24,
                left: _gutter,
                right: _gutter,
              ),
              // R2 #21 — short tagline, centred, one line.
              child: Align(
                alignment: Alignment.topCenter,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Balance and Stability for a Better Life!'.tr,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: headingStyle,
                  ),
                ),
              ),
            ),
          ),
          // R2 #23 — nothing on this screen scrolls.
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    _gutter,
                    16,
                    _gutter,
                    0,
                  ),
                  child: const Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _LanguageSelector(),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    _gutter,
                    0,
                    _gutter,
                    36, // R2 #22 — raised off the very bottom edge
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        // #39 — push, not offAllNamed, so Login keeps a back
                        // target.
                        onPressed: () => Get.toNamed('/login'),
                        style: ElevatedButton.styleFrom(
                          // Prefer the theme-adaptive accent over the
                          // deprecated constant `primary` (fixed colour,
                          // doesn't shift with brightness) — see
                          // AppThemeConfig's own migration note. `accent`/
                          // `onAccent` are the pair measured >=4.5:1 in both
                          // themes (6.87:1 / 8.33:1 light-dark for the fill;
                          // 7.54:1 / 7.72:1 for the text on it).
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
                          minimumSize: const Size.fromHeight(
                            52,
                          ), // clears the 44pt target
                        ),
                        child: Text('Continue with phone'.tr),
                      ),
                      const SizedBox(height: 14),
                      // Says out loud what the single button covers, so a
                      // returning user isn't left wondering where "Sign in"
                      // went. R2 #22: centred and a little larger.
                      Text(
                        'Sign in or create an account with your phone number.'
                            .tr,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ],
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
      // #38 follow-up — the surface must come from the THEME, not a literal.
      // It was a hard-coded dark navy (0xFF0E3B5C) while every label inside it
      // used AppThemeConfig.text(), which is DARK in light mode: on the
      // Motorola, in light mode, "Arabic" / "Kurdish Sorani" / "Kurdish
      // Badini" were dark grey on dark navy and effectively unreadable. Only
      // the selected row escaped it, because its badge lightens the strip
      // behind it — which is why this survived: the language you are already
      // using is always the legible one.
      //
      // Pairing the surface with the text colour means the two cannot drift
      // apart again, in either theme.
      color: AppThemeConfig.surface(context),
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
