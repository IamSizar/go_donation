import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

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

/// Picks one locale's value out of an `app_content`-shaped row.
///
/// WHY THIS IS NOT [localizedContentFromMap]
/// Two different column-naming conventions exist in this database and they must
/// not be confused. `partners`, `city_directory_entries` and the marriage
/// tables use `name` / `name_ar` / `name_sorani` / `name_badini`, which is what
/// [localizedContentFromMap] reads. `app_content` and `app_content_sections`
/// (migrations 025, 041, 099, 111, 112) use `_en` / `_ar` / `_ckb` / `_kmr`.
/// Pointing the wrong reader at either one silently returns the fallback for
/// every field.
///
/// [base] is the column stem — `title`, `body`, `address`. Falls back to
/// English when the current locale's value is blank, which is the same chain
/// the server's own `composeBody` applies, and returns an empty string when
/// there is nothing in either — so a caller can hide the block rather than
/// render an empty heading.
String localizedAppContent(Map<String, dynamic> row, String base) {
  final lang = AppLocaleService.assistantLang(); // en | ar | ckb | kmr
  final value = (row['${base}_$lang'] ?? '').toString().trim();
  if (value.isNotEmpty) return value;
  return (row['${base}_en'] ?? '').toString().trim();
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

/// Renders a backend TIMESTAMP as a date a human should read.
///
/// WHY THIS EXISTS
/// The same problem [localizedTag] solves, one field over. Go marshals
/// `time.Time` as RFC 3339, and several screens interpolated that string
/// straight into a label — a marketplace order read
/// "Submitted: 2026-08-15T12:15:35.660229Z" in the Arabic UI. That is a
/// machine value, in Latin digits, in a right-to-left interface.
///
/// [AppLocaleService.syncDateFormatLocale] already pins `Intl.defaultLocale`
/// on startup and on every language switch (both Kurdish variants fall back to
/// Arabic calendar data, since `intl` ships no Sorani/Badini month names), so a
/// bare [DateFormat] here is already locale-correct and needs no argument.
///
/// Falls back to the raw string if it will not parse, and to an empty string
/// for empty input, so a caller can hide the line rather than render a blank.
String localizedDate(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  // Two shapes reach this. Go's `time.Time` marshals to RFC 3339
  // ("2026-05-25T12:15:35Z"), which `DateTime.tryParse` reads; a few handlers
  // send a Postgres timestamp with a SPACE instead of the T, which it does
  // not. The second attempt is that case, and was the reason the donation
  // history kept its own parser.
  final parsed =
      DateTime.tryParse(value) ??
      DateTime.tryParse(value.replaceFirst(' ', 'T'));
  // Unparseable is better shown than swallowed — it means the server sent a
  // shape we do not know, and hiding it would hide the bug too.
  if (parsed == null) return value;
  return DateFormat('dd MMM yyyy').format(parsed.toLocal());
}

/// [localizedDate], with a translated word for the places where "no date" is
/// itself a value the user should read.
///
/// A volunteer mission with no fixed day is "Flexible", and the chip that says
/// so was written as `(mission['mission_date'] ?? 'Flexible').toString()` — a
/// bare English literal, so an Arabic reader got the English word even though
/// «مرن» has been in the map all along. [emptyKey] is a translation KEY for
/// that reason, and is only consulted when there is no value at all.
///
/// An unparseable date is NOT replaced by [emptyKey]: [localizedDate] returns
/// it verbatim on purpose, because a shape the app does not recognise means
/// the server sent something unexpected and hiding it would hide the bug.
String localizedDateOr(Object? raw, String emptyKey) {
  final shown = localizedDate(raw);
  return shown.isEmpty ? emptyKey.tr : shown;
}

/// [localizedDate] wrapped in a bidi isolate, for a date rendered INSIDE a
/// mixed sentence.
///
/// WHY THIS IS NOT PARANOIA
/// A date standing alone in its own `Text` needs nothing. A date joined to
/// other fields — `'$city - $date - $capacity'`, `'${'Next support due'.tr}:
/// $date'` — sits between bidi-neutral characters (the separator, the colon,
/// the spaces), and the Unicode bidi algorithm resolves a neutral run from
/// whatever is on either side of it. In an Arabic paragraph that can pull the
/// date's digits across the separator and print the parts of the line in an
/// order nobody wrote. Three defects of exactly this shape have been found in
/// this app already; the fix each time was an isolate.
///
/// U+2068 FIRST STRONG ISOLATE rather than U+2066 LEFT-TO-RIGHT ISOLATE,
/// because unlike the phone numbers and counts elsewhere in this codebase a
/// formatted date is not always LTR: it is "25 May 2026" in English and
/// «٢٥ مايو ٢٠٢٦» in Arabic. FSI takes its direction from the first strong
/// character of the content, so it is right in both. U+2069 POP DIRECTIONAL
/// ISOLATE closes it.
///
/// Returns '' for an empty date, so a caller's `isNotEmpty` guard still works
/// rather than seeing two invisible control characters.
String isolatedDate(Object? raw) {
  final shown = localizedDate(raw);
  if (shown.isEmpty) return '';
  // Written as escapes: the literal marks are invisible in a diff, and the
  // analyzer flags them.
  return '\u2068$shown\u2069';
}
