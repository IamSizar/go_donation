// Pins the step that asks what kind of donation this is (M3).
//
// WHY THIS FILE EXISTS
// The client's donation note lists five ways to give and asks for them to be
// offered at the point of choosing. The app had no such step: Contribute →
// amount → Continue went straight to checkout, which stacked four unrelated
// selectors and never named cash / electronic / balance transfer as a choice
// — they were flat rows in the payment list. The in-kind form was in another
// module entirely, unreachable from the donation flow. And the widget actually
// called `_DonationTypeSelector` offered general / zakat / sadaqah from three
// `const` entries in the binary, months after migration 103 made that list a
// dashboard-managed table.
//
// SO THERE ARE TWO REGRESSIONS TO GUARD, AND THEY ARE DIFFERENT SHAPES
//   1. The five choices must be OFFERED, and each must lead somewhere real —
//      a channel with no payment method behind it is a control that does
//      nothing.
//   2. The giving type must come from the SERVER. A hardcoded list passes
//      every screenshot test ever written, so the guard is a type the binary
//      has never heard of arriving over HTTP and appearing on screen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/donations/models/donation_channel.dart';
import 'package:flutter_application_1/modules/donations/widgets/donation_type_field.dart';

import '../support/fake_http.dart';

/// The live catalogue's own `method_type` vocabulary, copied from
/// GET /api/payment-methods on the production backend. If the server grows a
/// sixth, this list is where the app finds out.
const _liveMethodTypes = <String>['cash', 'bank', 'card', 'wallet', 'mobile'];

/// GET /api/donation-types, including one type NO BUILD OF THIS APP KNOWS —
/// which is the whole point: staff added it from the dashboard.
const _typesWithDashboardAddition =
    '{"items": ['
    '{"id": 1, "slug": "general", "name_en": "General", "name_ar": "عام", '
    '"name_ckb": "گشتی", "name_kmr": "گشتی", "display_order": 1, '
    '"active": true},'
    '{"id": 4, "slug": "kaffara", "name_en": "Kaffara", "name_ar": "كفارة", '
    '"name_ckb": "", "name_kmr": "", "display_order": 4, "active": true}]}';

Widget _wrap(Widget child) => GetMaterialApp(
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: child,
);

/// Pumps [child] with every HTTP request answered per [overrides].
///
/// `HttpOverrides.global` rather than `runZoned`, because the widget's own
/// `initState` fires inside the tester's zone and would not inherit a zone
/// established around the pump call.
Future<void> _pumpWithHttp(
  WidgetTester tester,
  FakeHttpOverrides overrides,
  Widget child, {
  bool settle = true,
}) async {
  final previous = HttpOverrides.current;
  HttpOverrides.global = overrides;
  addTearDown(() => HttpOverrides.global = previous);
  await tester.pumpWidget(_wrap(child));
  if (settle) await tester.pumpAndSettle();
}

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  group('the five kinds map onto real server data', () {
    test(
      'every payment method the server serves reaches exactly one family',
      () {
        // The failure this catches: a `method_type` that belongs to no channel
        // is a method the donor can never select once the list is filtered, and
        // one that belongs to two is a method offered under contradictory
        // headings.
        const families = [
          DonationChannel.cash,
          DonationChannel.electronic,
          DonationChannel.balanceTransfer,
        ];
        for (final type in _liveMethodTypes) {
          final matched = families
              .where((c) => c.acceptsMethodType(type))
              .toList();
          expect(
            matched.map((c) => c.slug).toList(),
            hasLength(1),
            reason: 'method_type "$type" must land in exactly one family',
          );
        }
      },
    );

    test('supporting the organization accepts every way of paying', () {
      // It is a destination for money, not a payment family — filtering it
      // would leave the donor unable to pay for it at all.
      for (final type in _liveMethodTypes) {
        expect(
          DonationChannel.supportOrganization.acceptsMethodType(type),
          isTrue,
        );
      }
    });

    test('goods take no payment method and never reach checkout', () {
      expect(DonationChannel.inKind.isMoney, isFalse);
      for (final type in _liveMethodTypes) {
        expect(DonationChannel.inKind.acceptsMethodType(type), isFalse);
      }
    });

    test('only the organization channel files a gift as operational', () {
      for (final channel in DonationChannel.values) {
        expect(
          channel.donationKind,
          channel == DonationChannel.supportOrganization ? 'operational' : null,
          reason:
              'a cash or card gift re-filed as operational would leave the '
              'beneficiary fund and land in the running-costs section',
        );
      }
    });

    test('a project may be chosen on the three money channels only', () {
      expect(DonationChannel.cash.allowsProjectChoice, isTrue);
      expect(DonationChannel.electronic.allowsProjectChoice, isTrue);
      expect(DonationChannel.balanceTransfer.allowsProjectChoice, isTrue);
      // Running costs are not a project, and goods do not go through checkout.
      expect(DonationChannel.supportOrganization.allowsProjectChoice, isFalse);
      expect(DonationChannel.inKind.allowsProjectChoice, isFalse);
    });
  });

  group('the five read as words in both languages', () {
    final en = AppTranslations().keys['en_US']!;
    final ar = AppTranslations().keys['ar_SA']!;

    test('each label has an English entry, so `.tr` is not a no-op', () {
      for (final channel in DonationChannel.values) {
        expect(
          en.containsKey(channel.titleKey),
          isTrue,
          reason: '${channel.slug} title',
        );
        expect(
          en.containsKey(channel.subtitleKey),
          isTrue,
          reason: '${channel.slug} subtitle',
        );
      }
    });

    test('none of them renders English on an Arabic screen', () {
      for (final channel in DonationChannel.values) {
        for (final key in [channel.titleKey, channel.subtitleKey]) {
          expect(ar[key], isNotNull, reason: key);
          expect(
            RegExp(r'[A-Za-z]').hasMatch(ar[key]!),
            isFalse,
            reason: 'Latin letters reached the Arabic label for $key',
          );
        }
      }
    });
  });

  group('the giving type comes from the dashboard, not the binary', () {
    testWidgets('a type staff added is offered to the donor', (tester) async {
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _typesWithDashboardAddition),
        Scaffold(
          body: DonationTypeField(
            selectedSlug: 'general',
            accentColor: Colors.teal,
            onSelected: (_) {},
          ),
        ),
      );

      // "Kaffara" appears in no Dart file. It exists only in the fake
      // response, so finding it on screen proves the list was read from the
      // server rather than from a `const` in the widget — which is exactly
      // what migration 103 was written to make possible.
      expect(find.text('Kaffara'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      // And the three that used to be hardcoded are no longer conjured up when
      // the server does not send them.
      expect(
        find.text('Zakat'),
        findsNothing,
        reason:
            'Zakat is absent from this response; showing it anyway would mean '
            'the list is still coming from the binary',
      );
    });

    testWidgets('a retired type is not left selected on the form', (
      tester,
    ) async {
      String? reselected;
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _typesWithDashboardAddition),
        Scaffold(
          body: DonationTypeField(
            // Staff deactivated 'sadaqah'; the form still holds it.
            selectedSlug: 'sadaqah',
            accentColor: Colors.teal,
            onSelected: (slug) => reselected = slug,
          ),
        ),
      );

      expect(
        reselected,
        'general',
        reason:
            'a donation carrying a retired slug is filed under the server '
            'fallback without the donor ever being told',
      );
    });

    testWidgets('a failed type load offers a retry', (tester) async {
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.serverError),
        Scaffold(
          body: DonationTypeField(
            selectedSlug: 'general',
            accentColor: Colors.teal,
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.byType(AppErrorState), findsOneWidget);
    });

    testWidgets('an empty catalogue says what will happen to the gift', (
      tester,
    ) async {
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: '{"items": []}'),
        Scaffold(
          body: DonationTypeField(
            selectedSlug: 'general',
            accentColor: Colors.teal,
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.byType(AppErrorState), findsNothing);
      expect(
        find.textContaining('recorded as a general donation'),
        findsOneWidget,
      );
    });
  });
}
