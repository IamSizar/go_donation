// The first execution of any kind for the beneficiary and volunteer homes.
//
// WHY THIS FILE EXISTS
// Every runtime test of this app has been performed as ONE account, a donor.
// There is no beneficiary or volunteer login to hand over, so
// `_buildBeneficiaryDashboard` and `_buildVolunteerDashboard` — and the panels,
// stat cells and activity tiles they alone reach — had never been built by
// anything: not by a person, not by a test. Two roles' home screens were
// shipping on the strength of the donor branch next to them compiling.
//
// A widget test cannot log in as a beneficiary, and this file does not pretend
// to. What it CAN do is build those subtrees and measure four properties that
// have each produced a real, reported defect on this codebase already:
//
//   1. NO ENGLISH ON THE ARABIC SCREEN. `.tr` on a key with no entry returns
//      the key, silently. Nothing fails; the screen just renders English.
//   2. NO PAIR BELOW ITS WCAG FLOOR. The three worst measured on this app —
//      1.04:1, 1.2:1, 2.25:1 — were all valid palette colours on the wrong
//      surface, which is invisible to a token-level guard.
//   3. NO OVERFLOW THE ROLE ADDS, in both languages and at two widths, judged
//      against the donor home as a control. See the overflow group for why the
//      control is not optional under `flutter test`'s square font.
//   4. FOUR STATES, with error checked BEFORE empty — so a failed load never
//      renders as "you have nothing".
//
// Every group pumps in BOTH languages: English strings are the longer ones and
// wrap where Arabic does not, and Arabic is the only pump that can see an
// untranslated string at all.
//
// WHAT IT DOES NOT PROVE
// Nothing about the endpoints, the permissions or the flow. The HTTP layer is
// a fake, so a route that 403s for a beneficiary, a summary the server never
// populates, a stat the backend never fills in, or a button that leads
// somewhere broken all pass here. Nor does it prove the app LOOKS right: the
// test font is one em per glyph, so line breaks and truncation points are not
// the device's. This is the subset of "has anyone ever run this code" that is
// reachable without an account, and it is not a substitute for one.
import 'dart:convert';
import 'dart:io';

import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/campaigns_api_client.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/widgets/dashboard.dart';

import '../support/fake_http.dart';
import '../support/rendered_tree.dart';

// ─── Fixtures ───

/// Server content is written in Arabic on purpose.
///
/// The Arabic pump fails on any Latin letter it finds, so English fixture data
/// would fail the test for the fixture's sake and teach nothing. Real rows
/// carry `title_ar`; these stand in for a tenant whose data is filled in.
const _arabicName = 'زيد العراقي';

/// The keys every consumer on this screen reads, so ONE body can answer them
/// all — which is what [FakeHttpOverrides] offers.
///
/// Home is not one request. It is the role summary (`success`/`role_key`/
/// `summary`), the news strip (`items`), the public impact slider (`stats`) and
/// the featured-campaigns carousel. `items` is empty and `stats` is absent on
/// purpose: those two strips are shared with the donor home and already
/// covered, so they are held in their quietest honest state rather than filled
/// with fixtures that would drown the role-specific panels this file exists to
/// measure — the news strip hides itself and the impact slider does too.
///
/// THE CAMPAIGNS CAROUSEL IS ALWAYS IN ITS ERROR STATE HERE, and that is a
/// property of the harness rather than a choice. It is the one caller on this
/// screen that uses Dio instead of package:http, and `FakeHttpOverrides`
/// implements only the two `HttpClient` members package:http touches
/// (`openUrl` and `close`) — everything else falls through to
/// `super.noSuchMethod`, which throws. The controller catches that and reports
/// "could not load campaigns", so the carousel renders its error banner with a
/// retry. Left as is deliberately: the alternative is teaching the shared fake
/// the whole of `HttpClient`, which would change what every other suite in this
/// repo sees, and an error state on a shared strip is a real state worth having
/// under the contrast and translation walks anyway. It is why the four-states
/// assertions key off the summary's own message rather than `AppErrorState`.
const _sharedEnvelope = <String, dynamic>{
  'success': true, // ModuleApi.getObject / getItems gate on this
  'status': 'success',
  'csrf_token': 'test-token',
  'data': <dynamic>[],
  'items': <dynamic>[], // media posts: no news, so the strip hides itself
};

/// A beneficiary with cases and requests in flight.
///
/// Status tokens are the ones the server really writes — the enums in
/// backend/internal/handlers/admin_status.go — because `localizedTag` degrades
/// an UNKNOWN tag to humanised English by design, and inventing a token would
/// manufacture a leak the app would never show.
String _beneficiaryBody({bool populated = true}) => jsonEncode({
  ..._sharedEnvelope,
  'role_key': 'beneficiary',
  'summary': {
    'stats': {
      'active_cases': 3,
      'pending_requests': 2,
      'approved_cases': 5,
      'needs_changes_cases': 1,
      'approved_requests': 4,
      'open_support_tickets': 2,
    },
    if (populated)
      'recent_cases': [
        {
          'public_title': 'حالة أسرة نازحة في الموصل',
          'verification_status': 'needs_changes',
          'priority_level': 'high',
          'updated_at': '2026-03-04T09:00:00Z',
        },
        {
          'public_title': 'مساعدة علاجية عاجلة',
          'verification_status': 'under_review',
          'priority_level': 'medium',
          'updated_at': '2026-02-19T09:00:00Z',
        },
      ],
    if (populated)
      'recent_requests': [
        {
          'project_title': 'مشروع ترميم سقف المنزل',
          'amount_needed': 750000,
          'status': 'under_review',
          'updated_at': '2026-03-01T09:00:00Z',
        },
      ],
  },
});

/// A volunteer with an application on file and missions booked.
String _volunteerBody({
  bool populated = true,
  String applicationStatus = 'approved',
}) => jsonEncode({
  ..._sharedEnvelope,
  'role_key': 'volunteer',
  'summary': {
    'stats': {
      'application_status': applicationStatus,
      'active_missions': 2,
      'completed_missions': 7,
      'hours_served': '18',
      'available_missions': 4,
    },
    'application': {'city': 'الموصل', 'status': applicationStatus},
    if (populated)
      'upcoming_missions': [
        {
          'title': 'قافلة إغاثة شتوية',
          'signup_status': 'approved',
          'city': 'الموصل',
          'mission_date': '2026-03-12T09:00:00Z',
        },
        {
          'title': 'توزيع سلال غذائية',
          'signup_status': 'pending',
          'city': 'أربيل',
          'mission_date': '2026-04-02T09:00:00Z',
        },
      ],
  },
});

/// The DONOR home, used only as a control for the overflow check.
///
/// Deliberately shaped like the role fixtures — two activity tiles, Arabic
/// titles, real dates — so the two pumps differ in the role branch and in
/// nothing else. See the overflow group for why a control is needed at all.
String _donorBody() => jsonEncode({
  ..._sharedEnvelope,
  'role_key': 'donor',
  'summary': {
    'stats': {
      'successful_amount': 750000,
      'active_sponsorships': 2,
      'successful_count': 5,
      'pending_count': 1,
      'active_campaigns': 4,
      'pending_sponsorships': 2,
    },
    'recent_donations': [
      {
        'amount': 250000,
        'campaign_title': 'حملة كسوة الشتاء',
        'payment_status': '1',
        'transaction_date': '2026-03-04T09:00:00Z',
      },
      {
        'amount': 100000,
        'campaign_title': 'سلة غذائية للأسر',
        'payment_status': '2',
        'transaction_date': '2026-02-19T09:00:00Z',
      },
    ],
  },
});

/// The role under test, with everything a pump needs to stand it up.
class _Role {
  const _Role(this.key, this.roleId, this.body, this.emptyCopy);

  final String key;
  final String roleId;
  final String Function() body;

  /// The role's own "nothing here yet" strings, which must NOT appear while an
  /// error is on screen.
  final List<String> emptyCopy;
}

/// The control for the overflow check — never a subject of the others.
final _donorControl = _Role('donor', '1', _donorBody, const []);

final _roles = <_Role>[
  _Role('beneficiary', '2', () => _beneficiaryBody(), const [
    'No beneficiary cases yet.',
    'No submitted requests yet.',
  ]),
  _Role('volunteer', '3', () => _volunteerBody(), const [
    'No missions joined yet.',
  ]),
];

// ─── Harness ───

/// iPhone 17 Pro, the device the client's screenshots come from.
const _phone = Size(402, 874);

/// The narrowest phone the store still serves. English wraps here where Arabic
/// does not, which is the asymmetry that exposed the chevron collision.
const _narrow = Size(320, 640);

const _locales = <Locale>[AppLocaleService.english, AppLocaleService.arabic];

/// Stands the home dashboard up for one role, language, size and brightness,
/// runs [body] against it, and takes it down again.
///
/// WHY A WRAPPER RATHER THAN A PLAIN PUMP HELPER
/// Both controllers behind this screen poll on a `Timer.periodic`, and the test
/// binding asserts that no timer is pending — INSIDE the test body's own frame,
/// before any `addTearDown` callback runs. Cleanup registered the usual way is
/// therefore too late, and every test in the file failed on a pending timer
/// before this shape. `Get.deleteAll` runs each controller's `onClose`, which is
/// what actually cancels them; `Get.reset` alone drops the instance map and
/// leaves the timers running.
///
/// The app it builds mirrors main.dart rather than a bare GetMaterialApp: the
/// theme, the locale font and the localization delegates all change what gets
/// measured, and a harness that skips them measures a screen the app never
/// ships.
Future<List<String>> _withDashboard(
  WidgetTester tester, {
  required _Role role,
  required Locale locale,
  required Size size,
  required Brightness brightness,
  required FakeHttpOverrides http,

  /// False stops one pump short, leaving the summary still in flight — the
  /// state the loading assertion is about.
  bool settle = true,
  required Future<void> Function() body,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final previous = HttpOverrides.current;
  HttpOverrides.global = http;
  addTearDown(() => HttpOverrides.global = previous);

  // The campaigns client is a `static final Dio`, and Dio's IO adapter CACHES
  // the HttpClient it builds. Left alone, the first test's fake would answer
  // every later test in this file, making the carousel's state depend on test
  // order. A fresh adapter each pump makes each test see only its own fake.
  CampaignsApiClient.dio.httpClientAdapter = IOHttpClientAdapter();

  SharedPreferences.setMockInitialValues({
    'id_user': '7',
    'role_id': role.roleId,
    'name_user': _arabicName,
  });
  sharedPreferences = await SharedPreferences.getInstance();

  // main.dart pins Intl.defaultLocale on startup and on every language switch;
  // without it every DateFormat in the tree renders English month names and the
  // Arabic pump would report a leak the app does not have.
  await AppLocaleService.syncDateFormatLocale(locale);

  try {
    // Layout overflows are diverted for EVERY pump, not only the overflow
    // group's. Left alone they sit as pending exceptions and fail whichever
    // test happened to trigger them, so a translation check would report a
    // RenderFlex instead of a leak. Anything that is not an overflow is passed
    // straight back to the binding and still fails the test.
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
          home: const DashboardHomeSection(),
        ),
      );
      if (settle) {
        // Two pumps and a beat: the first paints the skeleton, the fetches
        // resolve on the microtask queue, and the beat lets the Obx rebuild
        // settle. pumpAndSettle is unusable here — the controllers poll forever.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }
      // Assertions belong INSIDE here: the cleanup below calls Get.reset(),
      // after which `.tr` has no translations left and returns its own key —
      // so an expectation written after the call would compare an Arabic screen
      // against an English string and fail for the wrong reason.
      await body();
      if (!settle) {
        // Even the unsettled case has to finish before teardown. ModuleApi
        // wraps every request in `Future.timeout`, and that timeout's Timer
        // counts as pending until the request completes — which the binding
        // treats as a leak and fails the test for.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }
    });
  } finally {
    Get.deleteAll(force: true);
    Get.reset();
  }
}

/// The summary region's own failure message, mirrored from
/// RoleDashboardController. Asserting on THIS rather than on `AppErrorState`
/// keeps the four-states checks pointed at the role summary: the campaigns
/// carousel on the same page renders its own error state, and a type-level
/// assertion could not tell the two apart.
const _summaryError = 'Could not load your dashboard.';

/// The colour the window paints when nothing in the ancestry is opaque.
Color _windowColor(WidgetTester tester) => Theme.of(
  tester.element(find.byType(DashboardHomeSection)),
).scaffoldBackgroundColor;

void main() {
  // ─── 1 · No English on the Arabic screen ───

  group('the Arabic dashboard contains no English', () {
    for (final role in _roles) {
      for (final size in const [_phone, _narrow]) {
        testWidgets('${role.key} at ${size.width.toInt()}px', (tester) async {
          final leaks = <String>{};
          await _withDashboard(
            tester,
            role: role,
            locale: AppLocaleService.arabic,
            size: size,
            brightness: Brightness.light,
            http: FakeHttpOverrides(HttpBehaviour.ok, body: role.body()),
            body: () async {
              await sweepScroll(tester, () async {
                for (final text in collectTexts(
                  tester,
                  fallback: _windowColor(tester),
                )) {
                  if (leaksEnglish(text.data)) leaks.add(text.data);
                }
              });
            },
          );

          expect(
            leaks.toList()..sort(),
            isEmpty,
            reason:
                'Latin letters reached the ${role.key} home in Arabic. Either a '
                'literal was never passed through `.tr`, or `.tr` was called on '
                'a key with no entry — GetX returns the key unchanged and says '
                'nothing about it.',
          );
        });
      }
    }
  });

  // The volunteer's Application status cell reads a backend enum, and the two
  // values a fixture would never think to use are the ones that leaked: the
  // EMPTY one, which is every volunteer who has not applied yet, and
  // 'inactive', which is a real value of volunteer_applications.status with no
  // entry in any map. Both rendered English on the Arabic home.
  group('the volunteer application status is Arabic for every enum value', () {
    for (final status in const ['', 'submitted', 'approved', 'inactive']) {
      testWidgets('status "$status"', (tester) async {
        await _withDashboard(
          tester,
          role: _roles.last,
          locale: AppLocaleService.arabic,
          size: _phone,
          brightness: Brightness.light,
          http: FakeHttpOverrides(
            HttpBehaviour.ok,
            body: _volunteerBody(applicationStatus: status),
          ),
          body: () async {
            final leaks = <String>{};
            await sweepScroll(tester, () async {
              for (final text in collectTexts(
                tester,
                fallback: _windowColor(tester),
              )) {
                if (leaksEnglish(text.data)) leaks.add(text.data);
              }
            });
            expect(
              leaks.toList()..sort(),
              isEmpty,
              reason:
                  'volunteer_applications.status = "$status" reached the '
                  'Arabic home as English',
            );
          },
        );
      });
    }
  });

  group('the English dashboard shows no raw keys', () {
    for (final role in _roles) {
      testWidgets(role.key, (tester) async {
        final rendered = <String>{};
        await _withDashboard(
          tester,
          role: role,
          locale: AppLocaleService.english,
          size: _phone,
          brightness: Brightness.light,
          http: FakeHttpOverrides(HttpBehaviour.ok, body: role.body()),
          body: () async {
            await sweepScroll(tester, () async {
              rendered.addAll(
                collectTexts(
                  tester,
                  fallback: _windowColor(tester),
                ).map((t) => t.data),
              );
            });
          },
        );

        expect(
          unresolvedKeyShapes(rendered),
          isEmpty,
          reason:
              'a snake_case token on screen is a translation key that resolved '
              'to itself — the English reader sees the key, and the Arabic '
              'reader sees English',
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
              final textFailures = <String>{};
              final iconFailures = <String>{};
              await _withDashboard(
                tester,
                role: role,
                locale: locale,
                size: _phone,
                brightness: brightness,
                http: FakeHttpOverrides(HttpBehaviour.ok, body: role.body()),
                body: () async {
                  await sweepScroll(tester, () async {
                    final fallback = _windowColor(tester);
                    textFailures.addAll(
                      contrastFailures(
                        collectTexts(tester, fallback: fallback),
                      ),
                    );
                    iconFailures.addAll(
                      iconContrastFailures(
                        collectIcons(tester, fallback: fallback),
                      ),
                    );
                  });
                },
              );

              expect(
                textFailures.toList()..sort(),
                isEmpty,
                reason:
                    'text below its floor on the ${role.key} home. Ratios are '
                    'measured after compositing every translucent layer, which '
                    'is the step a token-level guard cannot take.',
              );
              expect(
                iconFailures.toList()..sort(),
                isEmpty,
                reason:
                    'a meaningful icon below 3:1 (WCAG 1.4.11). Glyphs under '
                    '50% opacity count as decoration and are excluded.',
              );
            },
          );
        }
      }
    }
  });

  // ─── 3 · No overflow ───

  group('the role branch adds no overflow of its own', () {
    // WHY THIS IS MEASURED AGAINST THE DONOR HOME RATHER THAN AGAINST ZERO
    //
    // `flutter test` renders with the test font, whose every glyph is exactly
    // one em wide. SF Pro averages nearer 0.55em, so Latin text in a widget
    // test is roughly twice its real width and Arabic wider still. At 320px
    // that inflation alone pushes the SHARED activity tile over its row by
    // 7–20px — measured — while the same tile has ~67px of headroom on a
    // device. Asserting "zero overflow" would therefore assert something false
    // about the app and invite someone to fix a layout that is not broken.
    //
    // The donor home is the control because it is the only branch of this
    // screen that has been run on a real device, at these widths, in both
    // languages, with no overflow reported. It is pumped with a deliberately
    // similar fixture, so the two runs share the font, the widths, the locale
    // and every shared widget — and differ only in the role branch. Anything
    // the beneficiary or volunteer branch overflows that the donor does not is
    // a layout difference the role introduced, which is exactly what this file
    // is looking for.
    //
    // At the device width the bar is absolute as well: the role branches
    // overflow nothing there, control or no control, and that is worth pinning.
    for (final role in _roles) {
      for (final locale in _locales) {
        for (final size in const [_phone, _narrow]) {
          testWidgets(
            '${role.key} · ${locale.languageCode} · ${size.width.toInt()}px',
            (tester) async {
              Future<Set<String>> sitesFor(_Role subject) async {
                final sites = await _withDashboard(
                  tester,
                  role: subject,
                  locale: locale,
                  size: size,
                  brightness: Brightness.light,
                  http: FakeHttpOverrides(
                    HttpBehaviour.ok,
                    body: subject.body(),
                  ),
                  body: () async {
                    await sweepScroll(tester, () async {});
                  },
                );
                return sites.map(overflowSite).toSet();
              }

              final roleSites = await sitesFor(role);
              final donorSites = await sitesFor(_donorControl);

              expect(
                (roleSites.difference(donorSites).toList())..sort(),
                isEmpty,
                reason:
                    'the ${role.key} home overflows at a widget the donor home '
                    'does not, at ${size.width.toInt()}px in '
                    '${locale.languageCode} — same font, same width, same '
                    'shared widgets, so the role branch is the difference',
              );
              if (size == _phone) {
                expect(
                  (roleSites.toList())..sort(),
                  isEmpty,
                  reason:
                      'nothing on the ${role.key} home may overflow at the '
                      'device width, control or no control',
                );
              }
            },
          );
        }
      }
    }
  });

  // ─── 4 · Four states, error before empty ───

  group('the summary region has all four states', () {
    for (final role in _roles) {
      testWidgets(
        '${role.key} — a failed load offers a retry, not an empty screen',
        (tester) async {
          await _withDashboard(
            tester,
            role: role,
            locale: AppLocaleService.arabic,
            size: _phone,
            brightness: Brightness.light,
            http: FakeHttpOverrides(HttpBehaviour.serverError),
            body: () async {
              expect(
                find.text(_summaryError.tr),
                findsOneWidget,
                reason: 'the summary failed and said nothing about it',
              );
              expect(
                find.text('retry'.tr),
                findsWidgets,
                reason: 'an error with no way out is a dead end (rule 5.7)',
              );
              for (final copy in role.emptyCopy) {
                expect(
                  find.text(copy.tr),
                  findsNothing,
                  reason:
                      'the error branch must be checked BEFORE the empty one — '
                      '"$copy" tells a user whose request merely failed that '
                      'they have nothing, which is a different and false claim',
                );
              }
            },
          );
        },
      );

      testWidgets(
        '${role.key} — the first paint is a skeleton, not a blank screen',
        (tester) async {
          await _withDashboard(
            tester,
            role: role,
            locale: AppLocaleService.arabic,
            size: _phone,
            brightness: Brightness.light,
            http: FakeHttpOverrides(HttpBehaviour.ok, body: role.body()),
            // Stops before the fetch resolves — the state a slow connection
            // holds on screen for seconds.
            settle: false,
            body: () async {
              expect(
                find.byType(AppSkeleton),
                findsWidgets,
                reason: 'a blank screen while loading violates rule 5.8',
              );
            },
          );
        },
      );

      testWidgets(
        '${role.key} — an empty result is a designed empty state, not nothing',
        (tester) async {
          await _withDashboard(
            tester,
            role: role,
            locale: AppLocaleService.arabic,
            size: _phone,
            brightness: Brightness.light,
            http: FakeHttpOverrides(
              HttpBehaviour.ok,
              body: role.key == 'beneficiary'
                  ? _beneficiaryBody(populated: false)
                  : _volunteerBody(populated: false),
            ),
            body: () async {
              // The empty panels sit below the fold, and a ListView does not
              // build what it does not show — an unscrolled `find.text` reports
              // them missing whether they exist or not.
              final rendered = <String>{};
              await sweepScroll(tester, () async {
                rendered.addAll(
                  collectTexts(
                    tester,
                    fallback: _windowColor(tester),
                  ).map((t) => t.data),
                );
              });

              for (final copy in role.emptyCopy) {
                expect(
                  rendered,
                  contains(copy.tr),
                  reason:
                      'an empty list must say so in words — "$copy" — rather '
                      'than render an empty panel',
                );
              }
              expect(
                rendered,
                isNot(contains(_summaryError.tr)),
                reason: 'a successful empty result is not an error',
              );
            },
          );
        },
      );
    }
  });
}
