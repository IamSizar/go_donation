// Regression guard for OPOS #25612.
//
// THE BUG
// The Arabic-script font (`Kurdfont.ttf`) was bundled at a single weight
// (400) in pubspec.yaml. `AppThemeConfig.applyLocaleFont` only swaps the
// `fontFamily` string on every TextStyle — it never touches `fontWeight` —
// so a style built with FontWeight.w600 kept asking for weight 600 of a
// font that had no weight-600 asset registered. Flutter/Skia then
// synthesized (faux-bolded) that weight from the single 400 glyph outline
// instead of rendering real w600 letterforms, which visibly damages Arabic
// script more than Latin.
//
// THE FIX
// `NotoKufiArabic` is registered in pubspec.yaml as a variable font at
// weights 300/400/600 (the exact set core/design/tokens.dart's AppType.*
// constants use), all pointing at the same
// assets/fonts/NotoKufiArabic-Variable.ttf file — the supported Flutter
// pattern for one variable-font asset serving multiple `weight:` entries.
//
// This test proves both halves stayed intact after the swap: the resolved
// TextStyle carries the new family name, AND its FontWeight survives
// untouched (applyLocaleFont must never silently drop or alter weight).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';

void main() {
  test(
    'Arabic locale resolves NotoKufiArabic without losing FontWeight.w600',
    () {
      final baseTheme = AppThemeConfig.buildTheme(Brightness.light);
      final arabicTheme = AppThemeConfig.applyLocaleFont(
        baseTheme,
        const Locale('ar'),
      );

      final headline = arabicTheme.textTheme.headlineMedium;
      expect(headline, isNotNull);
      expect(
        headline!.fontFamily,
        'NotoKufiArabic',
        reason:
            'Arabic-locale text must resolve to the multi-weight family, '
            'not the platform default or the retired single-weight Kurdfont.',
      );
      expect(
        headline.fontWeight,
        FontWeight.w600,
        reason:
            'applyLocaleFont only swaps fontFamily — the w600 the type '
            'scale asked for must still be w600 after the swap, so Flutter '
            'looks up the real w600 glyphs NotoKufiArabic now ships instead '
            'of synthesizing them.',
      );
    },
  );

  test('a non-Arabic locale is left on the platform default font', () {
    final baseTheme = AppThemeConfig.buildTheme(Brightness.light);
    final englishTheme = AppThemeConfig.applyLocaleFont(
      baseTheme,
      const Locale('en'),
    );

    expect(
      englishTheme.textTheme.headlineMedium?.fontFamily,
      isNot('NotoKufiArabic'),
      reason:
          'Only ar/ckb/kmr (registered as ar/ar_IQ/ar_TR) should get the '
          'Arabic-script family swap.',
    );
  });
}
