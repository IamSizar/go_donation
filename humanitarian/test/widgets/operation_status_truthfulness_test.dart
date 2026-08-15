// Pins that the coloured operation-status indicator describes what it is
// actually measuring.
//
// WHY THIS FILE EXISTS (K5)
// The client asked for a colour-coded operation status — green when the
// donation has been delivered in full, red when the family has received
// nothing, orange when part of it has arrived — with the number inside the
// colour.
//
// The badge that was built says exactly those three things. What it was fed
// does not mean any of them: both call sites passed `campaign.fundedProgress`,
// which is money raised ÷ goal. So a campaign that had collected its target
// but distributed nothing showed a green disc reading "تم التسليم بالكامل".
// That is not a missing feature — it is a false statement, on the Home screen,
// about the one thing a donor is trying to find out.
//
// Two halves, both pinned here:
//
//   1. The badge no longer guesses. `kind` is REQUIRED, so a call site has to
//      say whether its number is delivery progress or funding progress, and
//      the words follow from that. The old implicit default is what let a
//      funding number wear delivery words for as long as it did.
//
//   2. A real delivery signal exists and was being ignored. `donations`
//      has carried `delivery_status` since migration 001 (widened to eight
//      values in migration 050), and /api/donate/my_donations returns it on
//      every row — but `DonationHistoryEntry` parsed `payment_status` and
//      called it "Status", while the screen's own empty state promised the
//      donor "its reference code and delivery status". The report's claim that
//      "no delivery-based status exists on donations" is wrong; it existed and
//      was dropped on the floor by the parser.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/donations/models/donation_history_models.dart';
import 'package:flutter_application_1/shared/widgets/operation_status_badge.dart';

Widget _wrap(Widget child) => GetMaterialApp(
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: Scaffold(body: Center(child: child)),
);

Finder _announcing(String phrase) => find.bySemanticsLabel(RegExp(phrase));

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

void main() {
  group('a funding number never wears delivery words', () {
    testWidgets('100% funded does not claim the aid was delivered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const OperationStatusBadge(
            progress: 1,
            kind: OperationStatusKind.funding,
          ),
        ),
      );
      await tester.pump();

      expect(
        _announcing('Delivered in full'),
        findsNothing,
        reason:
            'a campaign can hit its funding target having distributed nothing '
            '— this is the exact sentence the client was shown on Home',
      );
      expect(_announcing('Fully funded'), findsOneWidget);
    });

    testWidgets('0% funded does not claim the family received nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const OperationStatusBadge(
            progress: 0,
            kind: OperationStatusKind.funding,
          ),
        ),
      );
      await tester.pump();

      expect(_announcing('Not received yet'), findsNothing);
      expect(_announcing('Not funded yet'), findsOneWidget);
    });

    testWidgets('the delivery wording still exists for delivery data', (
      tester,
    ) async {
      // The vocabulary is not deleted — it is reserved for a number that
      // actually means delivery.
      await tester.pumpWidget(
        _wrap(
          const OperationStatusBadge(
            progress: 1,
            kind: OperationStatusKind.delivery,
          ),
        ),
      );
      await tester.pump();

      expect(_announcing('Delivered in full'), findsOneWidget);
    });

    testWidgets('the pill agrees with the badge about what it measures', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const OperationStatusPill(
            progress: 0.4,
            kind: OperationStatusKind.funding,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Partially funded'), findsOneWidget);
      expect(find.text('In progress'), findsNothing);
      // The number survives — it is the half of the client's request that was
      // never broken.
      expect(find.text('40%'), findsOneWidget);
    });
  });

  group('every funding call site declares itself', () {
    // A source test because the mistake is per call site, and a widget test
    // can only look at the call site it was handed.
    const callSites = <String>[
      'lib/widgets/dashboard.dart',
      'lib/modules/donations/screens/campaign_detail_screen.dart',
    ];

    test('nothing hands fundedProgress to the delivery wording', () {
      for (final path in callSites) {
        final source = _read(path);
        final uses = RegExp(
          r'OperationStatus(?:Badge|Pill)\((?:[^()]|\([^()]*\))*\)',
        ).allMatches(source).map((m) => m.group(0)!);

        for (final use in uses) {
          if (!use.contains('fundedProgress')) continue;
          expect(
            use.contains('OperationStatusKind.funding'),
            isTrue,
            reason:
                '$path passes fundedProgress (money raised ÷ goal) without '
                'declaring it as funding:\n$use',
          );
        }
      }
    });
  });

  group('the donor donation row carries the real delivery status', () {
    test('the eight backend values all parse', () {
      // The set is not a guess: it is the CHECK constraint from migration 050.
      const ladder = {
        'registered': DonationDeliveryStatus.registered,
        'received': DonationDeliveryStatus.received,
        'under_review': DonationDeliveryStatus.underReview,
        'delivered': DonationDeliveryStatus.delivered,
        'paused': DonationDeliveryStatus.paused,
        'suspended': DonationDeliveryStatus.suspended,
        'archived': DonationDeliveryStatus.archived,
        'cancelled': DonationDeliveryStatus.cancelled,
      };
      ladder.forEach((token, expected) {
        expect(donationDeliveryStatusFromApi(token), expected, reason: token);
      });
    });

    test('an absent or unknown value claims nothing at all', () {
      // Defaulting to 'registered' would print "nothing delivered yet" about a
      // donation whose state we do not know — a red indicator invented out of
      // a missing field.
      expect(donationDeliveryStatusFromApi(null), isNull);
      expect(donationDeliveryStatusFromApi(''), isNull);
      expect(donationDeliveryStatusFromApi('something_new'), isNull);
    });

    test('a paid-but-undelivered donation reads as exactly that', () {
      // The whole confusion in one row: payment cleared, nothing delivered.
      final entry = DonationHistoryEntry.fromJson({
        'id': 7,
        'amount': 25000,
        'payment_status': 1,
        'delivery_status': 'registered',
        'campaign_name': 'Winter Relief',
      });

      expect(entry.status, DonationRecordStatus.success);
      expect(entry.deliveryStatus, DonationDeliveryStatus.registered);
      expect(
        entry.deliveryStatus!.progress,
        0.0,
        reason: 'the client asked for red at "the family has received nothing"',
      );
    });

    test('the delivery ladder runs in order and ends at delivered', () {
      const ordered = [
        DonationDeliveryStatus.registered,
        DonationDeliveryStatus.received,
        DonationDeliveryStatus.underReview,
        DonationDeliveryStatus.delivered,
      ];
      final progresses = ordered.map((s) => s.progress!).toList();

      expect(progresses.first, 0.0);
      expect(progresses.last, 1.0);
      for (var i = 1; i < progresses.length; i++) {
        expect(
          progresses[i] > progresses[i - 1],
          isTrue,
          reason: 'the ladder must be monotonic: $progresses',
        );
      }
    });

    test('a stopped donation shows a word but no position on the ladder', () {
      // Cancelled / archived / paused / suspended are not steps toward
      // delivery. Giving them a percentage would be inventing a number.
      for (final s in [
        DonationDeliveryStatus.paused,
        DonationDeliveryStatus.suspended,
        DonationDeliveryStatus.archived,
        DonationDeliveryStatus.cancelled,
      ]) {
        expect(s.progress, isNull, reason: '$s');
        expect(s.labelKey.isNotEmpty, isTrue, reason: '$s');
      }
    });
  });

  group('the delivery words reach an Arabic reader', () {
    test('every status label resolves to Arabic, not to its token', () {
      final ar = AppTranslations().keys['ar_SA']!;
      for (final s in DonationDeliveryStatus.values) {
        final value = ar[s.labelKey];
        expect(
          value,
          isNotNull,
          reason:
              '${s.labelKey} has no Arabic entry, so `.tr` returns the raw '
              'backend token on an Arabic screen',
        );
        expect(
          RegExp(r'[A-Za-z]').hasMatch(value!),
          isFalse,
          reason: '${s.labelKey} still reads as English: $value',
        );
      }
    });
  });
}
