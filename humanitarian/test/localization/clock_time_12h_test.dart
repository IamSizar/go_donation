// The wire format, painted onto the screen.
//
// THE SHAPE OF THE BUG
// A volunteer's availability read "09:00-17:00" everywhere it appeared — in
// the picker's own From/To buttons and in the summary under "My volunteer
// application". Nobody here reads a schedule on a 24-hour clock; the owner
// asked for "9:00 AM – 5:00 PM", and the Arabic equivalent with ص/م.
//
// The cause was one function doing two jobs. `DayAvailability.fmt` built the
// zero-padded 24-hour string that `toJson` SENDS TO THE BACKEND, and the
// picker also used it for the labels it PAINTS. Fixing the display by changing
// `fmt` would have been the obvious move and the wrong one — it would have
// written 12-hour strings into the `availability_schedule` column, which the
// Go backend stores and which the admin dashboard's `scheduleSummary`
// (admin-web/src/lib/skillCatalogue.ts) prints back out verbatim. The stored
// value is shared with another reader, so formatting it at save time would
// make the data depend on the language of the phone that wrote it.
//
// So the half of this file that matters most is not the pretty output: it is
// the assertions that `fmt` and `toJson` STILL PRODUCE 24-HOUR "HH:MM". Those
// are the ones that fail if someone later "simplifies" the two formatters back
// into one, and the failure would otherwise be silent until data was corrupt.
//
// Digits are deliberately ASCII under Arabic ("9:00 ص", not «٩:٠٠ ص»). That is
// what this app already does with dates — `localizedDate` renders "25 مايو
// 2026" — and a time in Arabic-Indic numerals beside a date in ASCII ones on
// the same card would be the more visible inconsistency. Asserted below so the
// choice is on the record rather than an accident of the `intl` version.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/support/widgets/availability_schedule_picker.dart';

/// U+202F NARROW NO-BREAK SPACE — what CLDR puts between the time and the
/// English AM/PM marker, instead of an ordinary space. Spelled as an escape
/// and used in every English expectation below because the two are
/// indistinguishable on screen: an assertion written with a normal space fails
/// with a message showing two strings that look identical, which is a
/// genuinely horrible half hour. Arabic uses an ordinary space before «ص», so
/// the Arabic expectations do not need it.
const _nnbsp = '\u202f';

/// The stored shape the backend actually returns: 24-hour, zero-padded.
const _schedule = [
  {'day': 'mon', 'from': '09:00', 'to': '17:00'},
  {'day': 'sun', 'from': '09:00', 'to': '17:00'},
];

/// Switches BOTH the `.tr` locale and `intl`'s, which are separate settings.
/// A test that moved only `Get.locale` would leave `DateFormat` on whatever the
/// previous test left behind and pass or fail for the wrong reason — the app
/// keeps them in step through [AppLocaleService.syncDateFormatLocale], so the
/// test has to as well.
Future<void> _useLocale(Locale locale) async {
  Get.locale = locale;
  await AppLocaleService.syncDateFormatLocale(locale);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Get.clearTranslations();
    Get.addTranslations(AppTranslations().keys);
    await _useLocale(const Locale('en', 'US'));
  });

  tearDown(() async {
    await _useLocale(const Locale('en', 'US'));
    Get.reset();
  });

  // ─── The stored format, which must not move ───

  test('the WIRE format stays 24-hour HH:MM in every locale', () async {
    // This is the assertion that protects the data. If it fails, schedules are
    // being written in a shape the backend and the dashboard cannot read.
    for (final locale in [const Locale('en', 'US'), const Locale('ar', 'SA')]) {
      await _useLocale(locale);

      expect(DayAvailability.fmt(const TimeOfDay(hour: 9, minute: 0)), '09:00');
      expect(
        DayAvailability.fmt(const TimeOfDay(hour: 17, minute: 0)),
        '17:00',
      );
      expect(DayAvailability.fmt(const TimeOfDay(hour: 0, minute: 5)), '00:05');

      const day = DayAvailability(
        day: 'mon',
        from: TimeOfDay(hour: 9, minute: 0),
        to: TimeOfDay(hour: 17, minute: 30),
      );
      expect(day.toJson(), {'day': 'mon', 'from': '09:00', 'to': '17:30'});

      // No AM/PM marker of either language may reach the column.
      final json = day.toJson().values.join(' ');
      expect(RegExp('AM|PM|ص|م').hasMatch(json), isFalse);
    }
  });

  // ─── The displayed format ───

  test('English shows a 12-hour clock, not the stored 24-hour one', () {
    expect(localizedClockTime('09:00'), '9:00${_nnbsp}AM');
    expect(localizedClockTime('17:00'), '5:00${_nnbsp}PM');
    // The exact string the owner reported seeing must be gone.
    expect(localizedClockTime('17:00'), isNot(contains('17')));
  });

  test('Arabic gets ص/م and no Latin letters', () async {
    await _useLocale(const Locale('ar', 'SA'));

    final morning = localizedClockTime('09:00');
    final evening = localizedClockTime('17:00');

    expect(morning, contains('ص'));
    expect(evening, contains('م'));
    expect(
      RegExp(r'[A-Za-z]').hasMatch('$morning$evening'),
      isFalse,
      reason: 'AM/PM in Latin letters is the leak this whole suite exists for',
    );
    // Digits stay ASCII, matching the dates rendered beside them.
    expect(morning, contains('9:00'));
  });

  test('both Kurdish variants fall back to Arabic rather than English', () async {
    // `intl` ships no Sorani or Badini time data, so both locales are pinned to
    // Arabic's by `dateFormatLocale`. That fallback is deliberate and is the
    // only reason a Kurdish reader is not shown "AM"; no Kurdish AM/PM word has
    // been invented anywhere in this change.
    for (final locale in [
      AppLocaleService.kurdishSorani,
      AppLocaleService.kurdishBadini,
    ]) {
      await _useLocale(locale);
      final shown = localizedClockTime('09:00');
      expect(
        RegExp(r'[A-Za-z]').hasMatch(shown),
        isFalse,
        reason: '$locale fell through to the English AM/PM marker',
      );
    }
  });

  test('midnight and noon do not become 0 or 24', () {
    // The two hours a 24→12 conversion gets wrong when it is written by hand
    // with a `% 12`, which is the reason this is done by `intl` and not here.
    expect(localizedClockTime('00:00'), '12:00${_nnbsp}AM');
    expect(localizedClockTime('12:00'), '12:00${_nnbsp}PM');
    expect(localizedClockTime('00:30'), '12:30${_nnbsp}AM');
    expect(localizedClockTime('12:30'), '12:30${_nnbsp}PM');
    expect(localizedClockTime('23:59'), '11:59${_nnbsp}PM');
  });

  test('the shapes an older or hand-edited row can carry still parse', () {
    // A single-digit hour predates the picker's zero padding; the seconds form
    // is how a Postgres `time` column serialises.
    expect(localizedClockTime('9:00'), '9:00${_nnbsp}AM');
    expect(localizedClockTime('09:00:00'), '9:00${_nnbsp}AM');
  });

  test('an unusable value is shown, not swallowed', () {
    // Same policy as `localizedDate`: a shape we do not recognise means the
    // server sent something unexpected, and hiding it would hide that.
    expect(localizedClockTime('banana'), 'banana');
    expect(localizedClockTime('25:00'), '25:00');
    expect(localizedClockTime('09:77'), '09:77');
    // Empty stays empty so a caller's isNotEmpty guard keeps working.
    expect(localizedClockTime(null), '');
    expect(localizedClockTime('   '), '');
  });

  // ─── The range, and its bidi isolate ───

  test('a range is wrapped in ONE first-strong isolate', () {
    // Escapes rather than the literal marks, for the two reasons the source
    // gives where it writes them: they are invisible in a diff, and the
    // analyzer warns on a bare one (text_direction_code_point_in_literal).
    const fsi = '\u2068'; // FIRST STRONG ISOLATE
    const pdi = '\u2069'; // POP DIRECTIONAL ISOLATE

    final range = isolatedClockRange('09:00', '17:00');

    expect(range.startsWith(fsi), isTrue, reason: 'missing FSI');
    expect(range.endsWith(pdi), isTrue, reason: 'missing PDI');
    // One isolate around the pair, not one around each end — the dash between
    // them must be inside it, or it stays bidi-neutral and can be re-resolved.
    expect(fsi.allMatches(range).length, 1);
    expect(range, contains('9:00${_nnbsp}AM – 5:00${_nnbsp}PM'));
  });

  test(
    'a half-written range degrades to nothing rather than a dangling dash',
    () {
      expect(isolatedClockRange('09:00', ''), '');
      expect(isolatedClockRange(null, '17:00'), '');
      expect(isolatedClockRange(null, null), '');
    },
  );

  // ─── The surface the owner actually reported ───

  test(
    'the application card summary no longer prints the wire format',
    () async {
      await _useLocale(const Locale('ar', 'SA'));
      final summary = localizedScheduleSummary(_schedule);

      expect(
        summary.contains('09:00-17:00'),
        isFalse,
        reason: 'this is verbatim what the owner reported on the card',
      );
      expect(summary, contains('9:00 ص'));
      expect(summary, contains('5:00 م'));
      // The day names must survive the change — they were the previous fix.
      expect(summary, contains('إثن'));
      expect(RegExp(r'[A-Za-z]').hasMatch(summary), isFalse);
    },
  );

  test('the English summary reads as a sentence a person would write', () {
    final summary = localizedScheduleSummary(_schedule);
    expect(summary, contains('Mon'));
    expect(summary, contains('9:00${_nnbsp}AM – 5:00${_nnbsp}PM'));
    expect(summary.contains('09:00'), isFalse);
  });

  test('a day with no hours still names the day', () {
    // The summary's fallback: better one day name than a dangling separator.
    final summary = localizedScheduleSummary(const [
      {'day': 'mon'},
    ]);
    expect(summary, 'Mon');
  });
}
