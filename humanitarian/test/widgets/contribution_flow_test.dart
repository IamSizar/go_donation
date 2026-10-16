// R2 #47–55 — the donation flow is two steps: four plain ways to give, then
// one fixed page per way ending in the same button.
//
// These pin what the client asked for, in the shape that regresses silently:
//   * step 1 offers EXACTLY the four ways, with no explanation text under them;
//   * every page ends in «تأكيد المساهمة» and carries the operating-costs line;
//   * the removed things stay removed (donation type, «التبرع لمؤسسة»);
//   * the amount rules match the server's (#54: a valid IQD amount is never
//     silently emptied).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/donations/screens/donations_section.dart';
import 'package:flutter_application_1/modules/donations/widgets/contribution_kit.dart';



Widget _app(Widget home, {Locale locale = const Locale('ar', 'SA')}) =>
    GetMaterialApp(
      translations: AppTranslations(),
      locale: locale,
      home: home,
    );

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  group('step 1', () {
    testWidgets('offers exactly the four ways, in the client\'s order', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const DonationsSection()));
      await tester.pumpAndSettle();

      final titles = [
        'الدفع الإلكتروني',
        'تحويل رصيد',
        'التسليم النقدي المباشر',
        'المساهمات العينية',
      ];
      for (final t in titles) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      // Top-to-bottom order is the client's list.
      final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
      expect([...ys]..sort(), ys, reason: 'the four are out of order');
    });

    testWidgets('has no sentence under any option and no donation type', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const DonationsSection()));
      await tester.pumpAndSettle();

      // Only four tiles' titles + the page title — nothing explanatory.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      expect(texts.length, lessThanOrEqualTo(5), reason: '$texts');
      for (final gone in ['عام', 'زكاة', 'صدقة', 'التبرع لمؤسسة']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    });
  });

  group('the amount rules match the server', () {
    test('a large IQD amount is valid (it used to be silently emptied)', () {
      expect(ContributionAmountRow.validateAmount('1500000'), isNull);
      expect(ContributionAmountRow.validateAmount('9999999999'), isNull);
    });

    test('nothing, zero and over-the-ceiling are refused', () {
      expect(ContributionAmountRow.validateAmount(''), isNotNull);
      expect(ContributionAmountRow.validateAmount('0'), isNotNull);
      expect(ContributionAmountRow.validateAmount('10000000001'), isNotNull);
    });

    test('currency is exactly three letters', () {
      expect(ContributionAmountRow.validateCurrency('IQD'), isNull);
      expect(ContributionAmountRow.validateCurrency('usd'), isNull);
      expect(ContributionAmountRow.validateCurrency('IQ'), isNotNull);
      expect(ContributionAmountRow.validateCurrency(''), isNotNull);
    });
  });

  group('the fixed page frame', () {
    testWidgets('ends in one confirm button with the operating-costs line', (
      tester,
    ) async {
      var confirmed = 0;
      await tester.pumpWidget(
        _app(
          ContributionScaffold(
            title: 'x',
            onConfirm: () => confirmed++,
            children: const [SizedBox(height: 10)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('تأكيد المساهمة'), findsOneWidget);
      expect(
        find.text(
          'تنويه: يتم استقطاع نسبة بسيطة من التبرعات لتغطية التكاليف التشغيلية '
          'وضمان استمرار عمل المشروع.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('تأكيد المساهمة'));
      expect(confirmed, 1);
    });

    testWidgets('the in-kind frame has no operating-costs line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ContributionScaffold(
            title: 'x',
            showNotice: false,
            onConfirm: () {},
            children: const [SizedBox(height: 10)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('تنويه'), findsNothing);
    });

    testWidgets('the button is disabled while sending, so it cannot double-send',
        (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(
        _app(
          ContributionScaffold(
            title: 'x',
            submitting: true,
            onConfirm: () => confirmed++,
            children: const [SizedBox(height: 10)],
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      expect(confirmed, 0);
    });
  });

  test('every new string reads in Arabic', () {
    final en = AppTranslations().keys['en_US']!;
    final ar = AppTranslations().keys['ar_SA']!;
    const keys = [
      'Electronic payment',
      'Balance transfer',
      'Direct cash handover',
      'In-kind contributions',
      'Confirm contribution',
      kContributionNoticeKey,
      'Card type',
      'Top-up / direct transfer',
      'Send a card',
      'Our number',
      'Card serial number',
      'Photo of the items',
      'Contribution sent',
    ];
    for (final k in keys) {
      expect(en.containsKey(k), isTrue, reason: 'en: $k');
      expect(ar[k], isNotNull, reason: 'ar: $k');
      expect(
        RegExp(r'[A-Za-z]').hasMatch(ar[k]!),
        isFalse,
        reason: 'Latin letters reached the Arabic label for $k',
      );
    }
  });
}
