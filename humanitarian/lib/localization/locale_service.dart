import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/push_registration.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocaleService {
  static const String _storageKey = 'locale_code';
  static const Locale english = Locale('en', 'US');
  static const Locale arabic = Locale('ar', 'SA');
  static const Locale kurdishSorani = Locale('ar', 'IQ');
  static const Locale kurdishBadini = Locale('ar', 'TR');

  static const List<Locale> supportedLocales = [
    english,
    arabic,
    kurdishSorani,
    kurdishBadini,
  ];

  static String localeTag(Locale locale) {
    final countryCode = locale.countryCode;
    if (countryCode == null || countryCode.isEmpty) {
      return locale.languageCode;
    }
    return '${locale.languageCode}_$countryCode';
  }

  static String contentVariant(Locale? locale) {
    final tag = locale == null ? '' : localeTag(locale).toLowerCase();
    return switch (tag) {
      'ar_sa' => 'ar',
      'ar_iq' => 'sorani',
      'ar_tr' => 'badini',
      _ => 'en',
    };
  }

  static String contentLocaleTag(Locale? locale) {
    return switch (contentVariant(locale)) {
      'ar' => 'ar_SA',
      'sorani' => 'ar_IQ',
      'badini' => 'ar_TR',
      _ => 'en_US',
    };
  }

  /// Canonical language code used by the AI assistant and backend:
  /// `en | ar | ckb | kmr`. Resolves [locale] (or the live [Get.locale] when
  /// null) through [contentVariant] so Sorani (ar_IQ) and Badini (ar_TR) are
  /// distinguished even though both reuse the Arabic language code.
  static String assistantLang([Locale? locale]) {
    return switch (contentVariant(locale ?? Get.locale)) {
      'ar' => 'ar',
      'sorani' => 'ckb',
      'badini' => 'kmr',
      _ => 'en',
    };
  }

  static List<String> localizedVariantOrder(Locale? locale) {
    final variant = contentVariant(locale);
    return switch (variant) {
      'ar' => ['ar', 'en', 'sorani', 'badini'],
      'sorani' => ['sorani', 'badini', 'en', 'ar'],
      'badini' => ['badini', 'sorani', 'en', 'ar'],
      _ => ['en', 'ar', 'sorani', 'badini'],
    };
  }

  static List<String> localizedKeyOrder(String baseKey, Locale? locale) {
    return localizedVariantOrder(locale)
        .map((variant) {
          return switch (variant) {
            'ar' => '${baseKey}_ar',
            'sorani' => '${baseKey}_sorani',
            'badini' => '${baseKey}_badini',
            _ => baseKey,
          };
        })
        .toList(growable: false);
  }

  /// The locale to pass to `intl`'s `DateFormat`/`NumberFormat` (month
  /// names, digit grouping, etc). This is deliberately NOT the same as the
  /// app's own [Locale] objects above — those exist only so GetX can tell
  /// English/Arabic/Sorani/Badini apart for `.tr` lookups (all three
  /// Kurdish variants are registered under the `ar` language code, which
  /// `intl` has no month-name data for as "Sorani"/"Badini"). Kurdish falls
  /// back to Arabic's calendar data here, which is the standard choice for
  /// this region and far better than the English fallback that was
  /// shipping before (dates showing "Jan"/"Feb" regardless of language).
  static String dateFormatLocale(Locale? locale) {
    return contentVariant(locale) == 'en' ? 'en' : 'ar';
  }

  /// Every `DateFormat`/`NumberFormat` call in the app that doesn't pass an
  /// explicit locale (the majority of them) falls back to `Intl.defaultLocale`
  /// — which was never being set, so those always rendered in whatever
  /// locale `intl` happens to default to, ignoring the in-app language
  /// picker entirely. Call this once at startup (after [loadLocale]) and
  /// again from [changeLocale] whenever the user switches language.
  static Future<void> syncDateFormatLocale(Locale locale) async {
    final tag = dateFormatLocale(locale);
    await initializeDateFormatting(tag);
    Intl.defaultLocale = tag;
  }

  static Future<Locale> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = (prefs.getString(_storageKey) ?? '').replaceAll('-', '_');

    if (code == localeTag(kurdishSorani)) {
      return kurdishSorani;
    }
    if (code == localeTag(kurdishBadini)) {
      return kurdishBadini;
    }
    if (code == localeTag(arabic) || code == arabic.languageCode) {
      return arabic;
    }
    // A stored value always wins — the user picked it. Only when there is
    // none (first launch, or after clearing data) do we follow the device.
    if (code.isEmpty) {
      return deviceLocale();
    }

    return english;
  }

  /// The app language matching the phone's own language, or English when the
  /// device is set to something we don't ship.
  ///
  /// Read from PlatformDispatcher rather than the widget binding so it works
  /// during startup, before runApp. Kurdish has two codes in the wild: `ckb`
  /// is Sorani, `kmr` Kurmanji/Badini; bare `ku` is ambiguous and is treated
  /// as Sorani, the more widely tagged of the two.
  static Locale deviceLocale() {
    for (final l in PlatformDispatcher.instance.locales) {
      switch (l.languageCode.toLowerCase()) {
        case 'ar':
          return arabic;
        case 'ckb':
        case 'ku':
          return kurdishSorani;
        case 'kmr':
          return kurdishBadini;
      }
    }
    return english;
  }

  static Future<void> changeLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, localeTag(locale));
    await Get.updateLocale(locale);
    await syncDateFormatLocale(locale);
    // Phase 27.3 — re-register the FCM device row so future pushes use
    // the newly-picked language. No-op when the user isn't signed in.
    unawaited(PushRegistration.registerNow());
  }
}
