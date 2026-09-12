// OPOS #25281 — Arabic text was reported as "overlapping"/garbled. Root cause
// (see app_theme_config.dart's applyLocaleFont doc): swapping in the
// Arabic-script font family left the LATIN-tuned line-height untouched, so
// Arabic's taller x-height and diacritics rendered inside a line box sized
// for a shorter Latin one.
//
// This locks in the fix: Arabic-script locales (ar/ckb/kmr, all registered
// as an 'ar' language code — see AppLocaleService) get the wider
// AppType.lead*Ar values, and non-Arabic locales are unaffected.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baseTheme = AppThemeConfig.buildTheme(Brightness.light);

  test('a Latin locale keeps the Latin-tuned leading untouched', () {
    final themed = AppThemeConfig.applyLocaleFont(baseTheme, const Locale('en'));
    expect(themed.textTheme.displayLarge?.height, AppType.leadDisplay);
    expect(themed.textTheme.headlineMedium?.height, AppType.leadTitle);
    expect(themed.textTheme.headlineSmall?.height, AppType.leadTitle);
    expect(themed.textTheme.bodyLarge?.height, AppType.leadBody);
    expect(themed.textTheme.bodyMedium?.height, AppType.leadDense);
    expect(themed.textTheme.bodySmall?.height, AppType.leadDense);
  });

  test('an Arabic-script locale gets the wider Arabic leading', () {
    final themed = AppThemeConfig.applyLocaleFont(baseTheme, const Locale('ar'));
    expect(themed.textTheme.displayLarge?.height, AppType.leadDisplayAr);
    expect(themed.textTheme.headlineMedium?.height, AppType.leadTitleAr);
    expect(themed.textTheme.headlineSmall?.height, AppType.leadTitleAr);
    expect(themed.textTheme.bodyLarge?.height, AppType.leadBodyAr);
    expect(themed.textTheme.bodyMedium?.height, AppType.leadDenseAr);
    expect(themed.textTheme.bodySmall?.height, AppType.leadDenseAr);
    // Every Arabic leading value is wider than its Latin counterpart — the
    // bug was text rendering too TIGHT, so the fix must only ever loosen it.
    expect(AppType.leadDisplayAr, greaterThan(AppType.leadDisplay));
    expect(AppType.leadTitleAr, greaterThan(AppType.leadTitle));
    expect(AppType.leadBodyAr, greaterThan(AppType.leadBody));
    expect(AppType.leadDenseAr, greaterThan(AppType.leadDense));
  });

  test('an Arabic-script locale still swaps the font family', () {
    final themed = AppThemeConfig.applyLocaleFont(baseTheme, const Locale('ar'));
    expect(
      themed.textTheme.bodyLarge?.fontFamily,
      AppThemeConfig.arabicScriptFontFamily,
    );
  });

  test('a null locale is a no-op', () {
    final themed = AppThemeConfig.applyLocaleFont(baseTheme, null);
    expect(themed, same(baseTheme));
  });
}
