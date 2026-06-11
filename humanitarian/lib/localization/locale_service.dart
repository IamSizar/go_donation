import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/push_registration.dart';
import 'package:get/get.dart';
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

    return english;
  }

  static Future<void> changeLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, localeTag(locale));
    await Get.updateLocale(locale);
    // Phase 27.3 — re-register the FCM device row so future pushes use
    // the newly-picked language. No-op when the user isn't signed in.
    unawaited(PushRegistration.registerNow());
  }
}
