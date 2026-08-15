import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:get/get.dart';

String currentContentLocaleTag([Locale? locale]) {
  return AppLocaleService.contentLocaleTag(locale ?? Get.locale);
}

String localizedContentFromMap(
  Map<String, dynamic> item,
  String baseKey, {
  String fallback = '',
}) {
  final order = AppLocaleService.localizedKeyOrder(baseKey, Get.locale);
  for (final key in order) {
    final value = (item[key] ?? '').toString().trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return fallback;
}

String localizedContentFromValues({
  required String base,
  String arabic = '',
  String sorani = '',
  String badini = '',
  String fallback = '',
}) {
  final locale = Get.locale;
  final order = AppLocaleService.localizedVariantOrder(locale);
  for (final variant in order) {
    final value = switch (variant) {
      'ar' => arabic.trim(),
      'sorani' => sorani.trim(),
      'badini' => badini.trim(),
      _ => base.trim(),
    };
    if (value.isNotEmpty) {
      return value;
    }
  }
  return fallback;
}

/// Renders a backend TAG — an enum value or a legacy slug — as something a
/// human should read.
///
/// WHY THIS EXISTS
/// Several backend fields are machine tokens that were being printed straight
/// onto the screen: marketplace products carry a legacy free-text `category`
/// ('beauty_care', 'food_pantry', 'home_textiles') and media posts carry a
/// `post_type` ('activity', 'event', 'news', 'article'). Both rendered as-is,
/// so an Arabic user saw the literal string "beauty_care" on a product card
/// and "event" on a news card — English, snake_case, in a right-to-left UI.
/// That breaks the project's hard rule that the Arabic interface contains no
/// English.
///
/// Two steps, in order:
///   1. `.tr` — a translated label wins whenever one exists. Adding a locale
///      entry for a new backend value is then the whole fix.
///   2. Otherwise HUMANISE: underscores become spaces and the first letter is
///      capitalised, so an untranslated value degrades to "Beauty care"
///      rather than "beauty_care". Still English, but no longer machine
///      output, and it stays legible when a new tag appears server-side
///      before anyone has translated it.
///
/// Returns an empty string for an empty input, so callers can hide the chip
/// entirely rather than render a blank pill.
String localizedTag(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';

  final translated = value.tr;
  // GetX returns the key unchanged when there is no entry for it.
  if (translated != value) return translated;

  final spaced = value.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  if (spaced.isEmpty) return '';
  return spaced[0].toUpperCase() + spaced.substring(1);
}
