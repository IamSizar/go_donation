// The first execution of the beneficiary and volunteer registration sections.
//
// WHY THIS FILE EXISTS
// registration_form.dart is 4,847 lines, and two thirds of it sit behind a
// role gate nobody has ever opened. `if (_roleId == 2) ...[` runs from line
// 2047 to 3742 — identification, housing, education, employment, social,
// health, assets, needs and privacy for an Eligible Recipient — and
// `if (_roleId == 3) ...[` runs from there to the end for a Volunteer. The
// only account this app has been exercised with is a donor, whose branch is
// `_roleId == 1`, so those ~2,700 lines have never been built by anything.
//
// The gate reads `role_id` out of SharedPreferences, which a test can set. So
// the same four properties the role dashboards are measured for apply here,
// plus one this screen makes possible and the dashboards do not: a form field
// declares the keyboard it asks for, and rule 5.6 says that declaration is not
// optional. A field left on the alphabetic keyboard for a number is a defect
// you can only see by rendering the field.
//
// WHY THERE IS NO OVERFLOW CHECK HERE, UNLIKE THE ROLE DASHBOARDS
// It was written, measured and removed. Under `flutter test`'s font — one em
// per glyph, against SF Pro's ~0.55 — every `DropdownButtonFormField` on this
// screen overflows its row: 3 sites in the grantor branch, 18 in the
// beneficiary's, 8 in the volunteer's. The counts are IDENTICAL at 402px and
// at 320px, which is the tell: the overflow does not depend on the page width
// at all, it is the dropdown sizing itself to a hint the square font makes
// ~2x too wide ("Select governorate" is 19 glyphs, ~152px on a device and
// ~304px here). The donor-home trick that rescues the dashboard check does not
// work here either — each role block owns its OWN copies of the dropdowns, at
// its own source lines, so the control's sites never cancel the subject's.
// Asserting on any of it would report the harness, so nothing is asserted and
// the measurement is written down instead. What IS worth a human's attention:
// only 3 of the ~28 dropdowns on this form pass `isExpanded: true`, and
// without it a genuinely long item WILL overflow on a device. Today's items
// and hints are all short enough that it does not.
//
// WHAT IT DOES NOT PROVE
// That registration WORKS for these roles. Nothing here submits, so the
// payload, the server's validation, the admin review and the approval mail are
// all untouched. The admin's field rules are faked as "nothing hidden, nothing
// extra required", which is one configuration out of many. Nor does it prove
// the form LOOKS right, for the font reason above. This is "was this code ever
// run", not "does this flow work".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/auth/screens/registration_form.dart';

import '../support/fake_http.dart';
import '../support/rendered_tree.dart';

// ─── Fixtures ───

/// GET /api/registration/field-rules with the admin's switches all at rest.
///
/// Nothing hidden and nothing extra required, which renders the WIDEST version
/// of each role's section — every field the admin could switch off is on. That
/// is the configuration a test wants: hiding fields would hide the code under
/// test along with them.
const _fieldRules = '{"required": [], "hidden": [], "searchable": []}';

/// An Arabic name, so the prefilled `name_user` cannot itself be a Latin leak.
const _arabicName = 'زيد العراقي';

class _Role {
  const _Role(this.key, this.roleId, this.ownSection, this.otherSection);

  final String key;
  final String roleId;

  /// A section heading only this role's branch renders.
  final String ownSection;

  /// A section heading only the OTHER role's branch renders — the gate has to
  /// keep it off this screen.
  final String otherSection;
}

const _beneficiary = _Role(
  'beneficiary',
  '2',
  'reg_recipient_identification_section',
  'reg_volunteer_contact_section',
);
const _volunteer = _Role(
  'volunteer',
  '3',
  'reg_volunteer_contact_section',
  'reg_recipient_identification_section',
);

const _roles = <_Role>[_beneficiary, _volunteer];

// ─── Harness ───

/// iPhone 17 Pro, the device the client's screenshots come from.
const _phone = Size(402, 874);

/// The narrowest phone still served. Field labels are the longest strings on
/// this screen and English is the longer language, so this is where a label
/// row runs out of room first.
const _narrow = Size(320, 640);

const _locales = <Locale>[AppLocaleService.english, AppLocaleService.arabic];

/// Stands the registration form up for one role, language, size and
/// brightness, runs [body] against it, and takes it down again.
///
/// Returns the widget creation sites of every layout overflow reported while it
/// was up. Overflows are diverted for EVERY pump rather than only the overflow
/// group's, because a pending RenderFlex fails whichever test triggered it —
/// so a translation check would report a layout error instead of a leak.
Future<List<String>> _withForm(
  WidgetTester tester, {
  required _Role role,
  required Locale locale,
  required Size size,
  required Brightness brightness,
  required Future<void> Function() body,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final previous = HttpOverrides.current;
  HttpOverrides.global = FakeHttpOverrides(HttpBehaviour.ok, body: _fieldRules);
  addTearDown(() => HttpOverrides.global = previous);

  SharedPreferences.setMockInitialValues({
    'id_user': '7',
    'role_id': role.roleId,
    'name_user': _arabicName,
    'address_user': 'الموصل، حي الزهراء',
  });
  sharedPreferences = await SharedPreferences.getInstance();

  // main.dart pins Intl.defaultLocale on startup and on every language switch.
  // Without it the date-of-birth dropdowns render English month names and the
  // Arabic pump would report a leak the app does not have.
  await AppLocaleService.syncDateFormatLocale(locale);

  try {
    return await captureOverflowLocations(() async {
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: locale,
          fallbackLocale: AppLocaleService.english,
          supportedLocales: AppLocaleService.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppThemeConfig.buildTheme(brightness),
          builder: (context, child) => Theme(
            data: AppThemeConfig.applyLocaleFont(Theme.of(context), locale),
            child: child!,
          ),
          home: const RegistrationFormPage(),
        ),
      );
      // The field rules resolve on the microtask queue and setState the whole
      // form; the beat afterwards lets that second build settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      // Assertions belong INSIDE here: the cleanup below calls Get.reset(),
      // after which `.tr` has no translations left and returns its own key.
      await body();
    });
  } finally {
    Get.reset();
  }
}

/// The colour the window paints when nothing in the ancestry is opaque.
Color _windowColor(WidgetTester tester) => Theme.of(
  tester.element(find.byType(RegistrationFormPage)),
).scaffoldBackgroundColor;

/// Every string in the form, gathered by scrolling the whole of it.
Future<Set<String>> _sweepStrings(WidgetTester tester) async {
  final rendered = <String>{};
  await sweepScroll(tester, () async {
    rendered.addAll(
      collectTexts(tester, fallback: _windowColor(tester)).map((t) => t.data),
    );
  });
  return rendered;
}

/// The [TextField] carrying [hintKey] as its hint, or null when it is not on
/// screen.
///
/// Matched on the hint rather than by position: the alternative is pairing each
/// field with the `_label` above it by tree order, and a mispairing there would
/// read the wrong field's keyboard and PASS. A hint is unique per field.
TextField? _fieldWithHint(WidgetTester tester, String hintKey) {
  final hint = hintKey.tr;
  for (final widget in tester.widgetList<TextField>(find.byType(TextField))) {
    if (widget.decoration?.hintText == hint) return widget;
  }
  return null;
}

void main() {
  tearDown(Get.reset);

  // ─── 0 · The gate itself ───

  group('the role gate opens exactly one branch', () {
    for (final role in _roles) {
      testWidgets('${role.key} sees its own section and not the other\'s', (
        tester,
      ) async {
        await _withForm(
          tester,
          role: role,
          locale: AppLocaleService.arabic,
          size: _phone,
          brightness: Brightness.light,
          body: () async {
            final rendered = await _sweepStrings(tester);
            expect(
              rendered,
              contains(role.ownSection.tr),
              reason:
                  'role_id ${role.roleId} did not open the ${role.key} branch, '
                  'so everything else in this file would be measuring an empty '
                  'form and passing',
            );
            expect(
              rendered,
              isNot(contains(role.otherSection.tr)),
              reason:
                  'the other role\'s section rendered too — the gate is not a '
                  'gate',
            );
          },
        );
      });
    }
  });

  // ─── 1 · No English on the Arabic form ───

  group('the Arabic form contains no English', () {
    for (final role in _roles) {
      for (final size in const [_phone, _narrow]) {
        testWidgets('${role.key} at ${size.width.toInt()}px', (tester) async {
          await _withForm(
            tester,
            role: role,
            locale: AppLocaleService.arabic,
            size: size,
            brightness: Brightness.light,
            body: () async {
              final leaks = (await _sweepStrings(
                tester,
              )).where(leaksEnglish).toList()..sort();
              expect(
                leaks,
                isEmpty,
                reason:
                    'Latin letters reached the ${role.key} registration branch '
                    'in Arabic. Either a literal skipped `.tr`, or `.tr` was '
                    'called on a key with no entry — GetX returns the key '
                    'unchanged and says nothing.',
              );
            },
          );
        });
      }
    }
  });

  group('the English form shows no raw keys', () {
    for (final role in _roles) {
      testWidgets(role.key, (tester) async {
        await _withForm(
          tester,
          role: role,
          locale: AppLocaleService.english,
          size: _phone,
          brightness: Brightness.light,
          body: () async {
            expect(
              unresolvedKeyShapes(await _sweepStrings(tester)),
              isEmpty,
              reason:
                  'this screen labels almost every field with a `reg_*` key, so '
                  'a missing entry shows the key itself to an English reader — '
                  'and English to an Arabic one',
            );
          },
        );
      });
    }
  });

  // ─── 2 · No contrast pair below the floor ───

  group('every rendered pair clears its WCAG floor', () {
    for (final role in _roles) {
      for (final brightness in Brightness.values) {
        for (final locale in _locales) {
          testWidgets(
            '${role.key} · ${locale.languageCode} · ${brightness.name}',
            (tester) async {
              await _withForm(
                tester,
                role: role,
                locale: locale,
                size: _phone,
                brightness: brightness,
                body: () async {
                  final textFailures = <String>{};
                  final iconFailures = <String>{};
                  var measured = 0;
                  await sweepScroll(tester, () async {
                    final fallback = _windowColor(tester);
                    final texts = collectTexts(tester, fallback: fallback);
                    measured += texts.length;
                    textFailures.addAll(contrastFailures(texts));
                    iconFailures.addAll(
                      iconContrastFailures(
                        collectIcons(tester, fallback: fallback),
                      ),
                    );
                  });

                  expect(
                    measured,
                    greaterThan(50),
                    reason:
                        'a contrast walk that measures nothing passes for the '
                        'wrong reason — this form has hundreds of labels',
                  );
                  expect(
                    textFailures.toList()..sort(),
                    isEmpty,
                    reason:
                        'text below its floor on the ${role.key} registration '
                        'branch. Ratios are measured after compositing every '
                        'translucent layer, which is the step a token-level '
                        'guard cannot take.',
                  );
                  expect(
                    iconFailures.toList()..sort(),
                    isEmpty,
                    reason:
                        'a meaningful icon below 3:1 (WCAG 1.4.11). Glyphs '
                        'under 50% opacity count as decoration and are '
                        'excluded.',
                  );
                },
              );
            },
          );
        }
      }
    }
  });

  // ─── 3 · Each field asks for the right keyboard ───

  group('a number field opens a number pad', () {
    // Rule 5.6, and not a matter of taste on this screen: the SAME form already
    // gives TextInputType.number to family size, rooms, families, certificates,
    // working hours, wage, rental amount, housing area, height and weight. Any
    // numeric field left on the default keyboard is therefore an omission
    // rather than a decision — and every one of them is in a role block nobody
    // had rendered.
    testWidgets('the beneficiary\'s monthly income', (tester) async {
      await _withForm(
        tester,
        role: _beneficiary,
        locale: AppLocaleService.english,
        size: _phone,
        brightness: Brightness.light,
        body: () async {
          final field = _fieldWithHint(tester, 'reg_income_hint');
          expect(field, isNotNull, reason: 'the income field did not render');
          expect(
            field!.keyboardType,
            TextInputType.number,
            reason:
                'monthly income is an amount, and every other amount on this '
                'form asks for the number pad',
          );
        },
      );
    });

    testWidgets('the beneficiary\'s national ID', (tester) async {
      await _withForm(
        tester,
        role: _beneficiary,
        locale: AppLocaleService.english,
        size: _phone,
        brightness: Brightness.light,
        body: () async {
          final field = _fieldWithHint(
            tester,
            'reg_recipient_national_id_hint',
          );
          expect(field, isNotNull, reason: 'the ID field did not render');
          expect(
            field!.keyboardType,
            TextInputType.number,
            reason:
                'the volunteer branch asks for the number pad on the identical '
                'field (reg_volunteer_national_id), so the two disagree about '
                'the same document',
          );
        },
      );
    });

    testWidgets('the volunteer\'s national ID, which already did', (
      tester,
    ) async {
      // The one that was already right. Pinned so the fix above is understood
      // as making two branches agree, not as a new convention.
      await _withForm(
        tester,
        role: _volunteer,
        locale: AppLocaleService.english,
        size: _phone,
        brightness: Brightness.light,
        body: () async {
          final field = _fieldWithHint(
            tester,
            'reg_volunteer_national_id_hint',
          );
          expect(field, isNotNull, reason: 'the ID field did not render');
          expect(field!.keyboardType, TextInputType.number);
        },
      );
    });
  });
}
