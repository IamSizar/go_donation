import 'package:flutter_application_1/data/iraq_governorates.dart';
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

/// Renders a stored `HH:MM` CLOCK TIME as a 12-hour time a human should read.
///
/// WHY THIS EXISTS
/// The volunteer availability picker had exactly one time formatter,
/// `DayAvailability.fmt`, and it produced 24-hour `HH:MM`. That single function
/// was doing two unrelated jobs: building the value SENT TO THE BACKEND and
/// building the label PAINTED ON THE SCREEN. So every surface that showed a
/// volunteer's hours showed them as "09:00-17:00" \u2014 the wire format, leaked
/// onto the screen. The owner asked for "9:00 AM \u2013 5:00 PM"; a 24-hour clock
/// is not what people here read a schedule in.
///
/// WHY THE WIRE FORMAT MUST NOT FOLLOW
/// `DayAvailability.toJson` writes the same field, and that value is stored by
/// the Go backend and read back by the admin dashboard, whose `scheduleSummary`
/// in `admin-web/src/lib/skillCatalogue.ts` renders the `from`/`to` strings
/// VERBATIM into its own summary. So the stored value is not private to this
/// app: whatever is written into it is what a caseworker in the dashboard
/// reads. Formatting for display at save time would mean the column's contents
/// depended on the language the volunteer's phone happened to be in \u2014 an
/// application filed from an Arabic handset would show \u00ab9:00 \u0635\u00bb to an English
/// dashboard user, and the column would stop being a single comparable shape.
/// Keeping it 24-hour keeps one canonical value that each end formats for its
/// own reader. The display format is therefore a SEPARATE function, and this is
/// the one callers reach for; `fmt` stays 24-hour and stays pointed at
/// `toJson`.
///
/// WHY `intl` AND NOT A HAND-BUILT STRING
/// The AM/PM marker is a translated word \u2014 \u00ab\u0635\u00bb/\u00ab\u0645\u00bb in Arabic \u2014 and so is its
/// position relative to the digits. [AppLocaleService.syncDateFormatLocale]
/// already pins `Intl.defaultLocale` at startup and on every language switch
/// (both Kurdish variants fall back to Arabic, which `intl` has data for), so a
/// bare `DateFormat.jm()` here is already locale-correct and needs no argument
/// \u2014 the same arrangement [localizedDate] relies on one function up.
///
/// The date is a throwaway: `jm` is a TIME-only skeleton, so only the hour and
/// minute of the [DateTime] handed to it are ever read.
///
/// A NOTE ON DIGITS, because it looks like a bug and is not: under Arabic this
/// returns "9:00 \u0635" with ASCII digits rather than \u00ab\u0669:\u0660\u0660 \u0635\u00bb. That is what this
/// app already does everywhere else \u2014 `localizedDate` renders "25 \u0645\u0627\u064a\u0648 2026"
/// under the same locale \u2014 and matching the surrounding dates matters more
/// than the Arabic-Indic numerals, which would otherwise appear on the time
/// and nowhere else on the same card.
///
/// A SECOND NOTE ON INVISIBLE CHARACTERS, because this one costs an hour if
/// you meet it without warning: under English, CLDR separates the time from
/// the AM/PM marker with U+202F NARROW NO-BREAK SPACE, not an ordinary space —
/// so the result is "9:00 AM", which looks exactly like "9:00 AM" in a
/// diff, a terminal and a test failure message but is not equal to it. That is
/// deliberate upstream (it stops a line breaking between the digits and the
/// marker) and is left alone here. Arabic uses an ordinary space before «ص».
/// Anything comparing this output to a literal has to spell the escape out;
/// the tests in test/localization/clock_time_12h_test.dart do.
///
/// Falls back to the raw string when it will not parse and to '' for empty
/// input, so a caller's `isNotEmpty` guard keeps working. Unparseable is shown
/// rather than swallowed, for the reason [localizedDate] gives: a shape we do
/// not recognise means the server sent something unexpected, and hiding it
/// would hide the bug too.
String localizedClockTime(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  // Deliberately anchored and tolerant of a single-digit hour: the picker
  // always writes a zero-padded "09:00", but rows predating it \u2014 and anything
  // hand-edited in the database \u2014 can carry "9:00". Seconds are matched and
  // discarded because Postgres `time` columns serialise as "09:00:00".
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(value);
  if (match == null) return value;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  // A regex cannot express "0-23", so the range is checked here. "25:00" is
  // as unusable as "banana" and takes the same path.
  if (hour > 23 || minute > 59) return value;
  return DateFormat.jm().format(DateTime(2000, 1, 1, hour, minute));
}

/// A "from \u2013 to" pair of clock times, formatted for display and wrapped in a
/// single bidi isolate.
///
/// WHY THE ISOLATE, AND WHY AROUND THE WHOLE RANGE
/// This is the argument [isolatedDate] makes, and a formatted time is a
/// stronger case than a date. Under Arabic the result mixes ASCII digits
/// (bidi class EN) with an Arabic AM/PM marker (strong RTL) \u2014 genuinely
/// bidirectional text \u2014 and it is then joined into a longer subtitle by
/// bidi-NEUTRAL separators (the "\u060c " between days, the " - " between the
/// status, city and schedule). The Unicode bidi algorithm resolves a neutral
/// run from whatever sits either side of it, which is how three defects
/// already found in this app printed the parts of a line in an order nobody
/// wrote.
///
/// The isolate goes around the PAIR rather than around each time because the
/// two times and the dash between them are one unit of meaning: isolating them
/// separately would leave that dash neutral and free to be re-resolved,
/// which is the same bug one level down.
///
/// U+2068 FIRST STRONG ISOLATE, not U+2066 LEFT-TO-RIGHT ISOLATE, for
/// [isolatedDate]'s reason: the content is not always LTR. "9:00 AM \u2013 5:00 PM"
/// begins with a digit and resolves LTR; \u00ab9:00 \u0635 \u2013 5:00 \u0645\u00bb has \u00ab\u0635\u00bb as its first
/// strong character and resolves RTL, putting the start time at the Arabic
/// reading start. FSI is correct in both; a hardcoded LRI would be wrong in
/// Arabic. U+2069 POP DIRECTIONAL ISOLATE closes it.
///
/// Returns '' unless BOTH ends are present, so a half-written row degrades to
/// the day name alone rather than to a dangling dash.
String isolatedClockRange(Object? from, Object? to) {
  final start = localizedClockTime(from);
  final end = localizedClockTime(to);
  if (start.isEmpty || end.isEmpty) return '';
  // An EN DASH with spaces, matching the "Weekdays 9\u20135" preset chip beside it.
  // Punctuation, not a word, so it is the same in every locale.
  return '\u2068$start \u2013 $end\u2069';
}

/// A city as the reader should see it.
///
/// One of Iraq's eighteen governorates is a translation key and becomes
/// «أربيل»; anything else — a village, a district, a typo — is text the person
/// typed and is returned untouched. See governorateKeyFor for why the match is
/// case-insensitive: `city` is free text on several forms, so what is stored is
/// whatever was written, and a card calling `.tr` on `duhok` got `duhok` back.
String localizedCity(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  final key = governorateKeyFor(value);
  return key == null ? value : key.tr;
}
