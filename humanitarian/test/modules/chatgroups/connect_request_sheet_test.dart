// Pins the "Ask staff to connect me" sheet — OPOS #25284 Phase 5 Task 5
// (OPOS #26046).
//
// WHAT IS PINNED
//   1. Validation happens before the network: a blank or whitespace-only
//      message is refused at the field and no request is made.
//   2. A valid message is sent exactly once, trimmed, to the context the entry
//      point named; the sheet closes and a confirmation is shown — even when
//      the member closed the sheet while the request was in flight. That is
//      the part the old plan got wrong: it confirmed through the sheet's own
//      context, behind `if (mounted)`, so a request that landed after the
//      sheet was gone was sent without the member ever being told.
//   3. A server failure is told in the member's language, never as the raw
//      exception; the typed text survives and the button works again.
//   4. A second tap while the request is in flight sends nothing more.
//   5. Rule 5.6: dragging dismisses the keyboard, and the keyboard never covers
//      the field or the button.
//   6. Arabic: nothing on the sheet is written in Latin letters.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/connect_request_button.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/connect_request_sheet.dart';

import 'fake_chat_groups_api.dart';

const _submit = Key('connect_request_submit');
const _contextId = 42;

/// Pumps in short steps: long enough for the fake to answer and the sheet to
/// animate, without ever settling on the looping in-button spinner.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// What the root screen under the host says, so a test can tell whether the
/// host was popped off and uncovered it.
const _rootText = 'root screen';

/// Long enough for a dismissal to start the sheet's ~200 ms exit animation,
/// short enough that the sheet's state is still mounted.
const _insideExitAnimation = Duration(milliseconds: 50);

/// Opens the sheet the way a member does: by tapping the entry-point button
/// for donation [_contextId], on a screen that has a Scaffold to confirm on.
///
/// The host is PUSHED over a root screen, as a real detail screen is, so a
/// stray pop has a route to wrongly remove and a test can see it happen.
Future<void> _openSheet(
  WidgetTester tester,
  FakeChatGroupsApi api, {
  Locale locale = const Locale('en', 'US'),
}) async {
  Get.locale = locale;
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      translations: AppTranslations(),
      locale: locale,
      home: const Scaffold(body: Center(child: Text(_rootText))),
    ),
  );
  unawaited(
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: Center(
                child: ConnectRequestButton(
                  contextType: kConnectContextDonation,
                  contextId: _contextId,
                  api: api,
                ),
              ),
            ),
          ),
        ),
  );
  await _settle(tester);
  await tester.tap(find.byType(ConnectRequestButton));
  await _settle(tester);
}

/// Disposes the tree, so the confirmation's display timer is cancelled before
/// the test ends.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// The text currently in the message field.
String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

/// Every string drawn inside the sheet, labels and errors included.
List<String> _sheetTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(ConnectRequestSheet),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .toList();

void main() {
  final en = AppTranslations.englishForTest;
  final ar = AppTranslations.arabicForTest;

  setUp(() async {
    // isGuestMode() and the haptics' mute switch both read preferences.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
  });

  tearDown(Get.reset);

  testWidgets('a blank message is refused at the field and never sent', (
    tester,
  ) async {
    final api = FakeChatGroupsApi();
    await _openSheet(tester, api);

    await tester.enterText(find.byType(TextField), '   \n  ');
    await tester.tap(find.byKey(_submit));
    await _settle(tester);

    expect(find.text(en['connect_request_message_required']!), findsOneWidget);
    expect(api.submittedConnectRequests, isEmpty);
    expect(find.byType(ConnectRequestSheet), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a valid message is sent once, trimmed, then confirmed', (
    tester,
  ) async {
    final api = FakeChatGroupsApi();
    await _openSheet(tester, api);

    await tester.enterText(find.byType(TextField), '  Please connect me.  ');
    await tester.tap(find.byKey(_submit));
    await _settle(tester);

    expect(api.submittedConnectRequests, [
      (
        contextType: 'donation',
        contextId: _contextId,
        message: 'Please connect me.',
      ),
    ]);
    expect(find.byType(ConnectRequestSheet), findsNothing);
    expect(find.text(en['connect_request_sent']!), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a request that lands after the sheet was closed is confirmed', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeChatGroupsApi()..submitGate = gate;
    await _openSheet(tester, api);

    await tester.enterText(find.byType(TextField), 'Please connect me.');
    await tester.tap(find.byKey(_submit));
    await tester.pump();

    // The member taps the barrier above the sheet while it is still sending.
    await tester.tapAt(const Offset(AppSpace.lg, AppSpace.lg));
    await _settle(tester);
    expect(find.byType(ConnectRequestSheet), findsNothing);

    gate.complete();
    await _settle(tester);

    expect(api.submittedConnectRequests, hasLength(1));
    expect(find.text(en['connect_request_sent']!), findsOneWidget);
    await _close(tester);
  });

  testWidgets('an answer landing as the sheet closes never pops the screen '
      'underneath', (tester) async {
    final gate = Completer<void>();
    final api = FakeChatGroupsApi()..submitGate = gate;
    await _openSheet(tester, api);

    await tester.enterText(find.byType(TextField), 'Please connect me.');
    await tester.tap(find.byKey(_submit));
    await tester.pump();

    // The member taps the barrier while it is sending, and the answer lands
    // during the exit animation — while the sheet's state is still mounted.
    await tester.tapAt(const Offset(AppSpace.lg, AppSpace.lg));
    await tester.pump();
    await tester.pump(_insideExitAnimation);
    expect(find.byType(ConnectRequestSheet), findsOneWidget);

    gate.complete();
    await _settle(tester);

    expect(find.byType(ConnectRequestSheet), findsNothing);
    expect(
      find.byType(ConnectRequestButton),
      findsOneWidget,
      reason: 'the host screen under the sheet was popped',
    );
    expect(find.text(_rootText), findsNothing);
    // The sheet was gone before the answer, so the toast is the confirmation.
    expect(find.text(en['connect_request_sent']!), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a server failure keeps the text and lets the member retry', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..submitError = Exception('pq: duplicate key value violates constraint');
    await _openSheet(tester, api);

    await tester.enterText(find.byType(TextField), 'Please connect me.');
    await tester.tap(find.byKey(_submit));
    await _settle(tester);

    expect(
      find.textContaining(en['error_connect_request_submit_failed']!),
      findsOneWidget,
    );
    expect(find.textContaining('pq:'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(_fieldText(tester), 'Please connect me.');
    expect(find.byType(ConnectRequestSheet), findsOneWidget);

    // Usable again: the same tap now goes through.
    api.submitError = null;
    await tester.tap(find.byKey(_submit));
    await _settle(tester);

    expect(api.submittedConnectRequests, hasLength(2));
    expect(find.byType(ConnectRequestSheet), findsNothing);
    await _close(tester);
  });

  testWidgets('a second tap while sending sends nothing more', (tester) async {
    final gate = Completer<void>();
    final api = FakeChatGroupsApi()..submitGate = gate;
    await _openSheet(tester, api);

    await tester.enterText(find.byType(TextField), 'Please connect me.');
    await tester.tap(find.byKey(_submit));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(_submit), warnIfMissed: false);
    await tester.pump();
    expect(api.submittedConnectRequests, hasLength(1));

    gate.complete();
    await _settle(tester);

    expect(api.submittedConnectRequests, hasLength(1));
    await _close(tester);
  });

  group('keyboard', () {
    testWidgets('dragging the sheet dismisses the keyboard', (tester) async {
      await _openSheet(tester, FakeChatGroupsApi());

      final scroll = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(ConnectRequestSheet),
          matching: find.byType(SingleChildScrollView),
        ),
      );

      expect(
        scroll.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      await _close(tester);
    });

    testWidgets('the keyboard covers neither the field nor the button', (
      tester,
    ) async {
      // A portrait phone, 390x844 logical, with a 300pt keyboard.
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = const Size(1170, 2532);
      addTearDown(tester.view.reset);
      await _openSheet(tester, FakeChatGroupsApi());

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await _settle(tester);

      const keyboardTop = 844.0 - 300.0;
      expect(
        tester.getRect(find.byType(TextField)).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      expect(
        tester.getRect(find.byKey(_submit)).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      await _close(tester);
    });
  });

  testWidgets('in Arabic nothing on the sheet is written in Latin letters', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()..submitError = Exception('Database error');
    await _openSheet(tester, api, locale: const Locale('ar', 'SA'));
    final latin = RegExp(r'[A-Za-z]');

    // As opened, then with the blank-message refusal showing.
    await tester.tap(find.byKey(_submit));
    await _settle(tester);
    expect(find.text(ar['connect_request_message_required']!), findsOneWidget);
    for (final text in _sheetTexts(tester)) {
      expect(latin.hasMatch(text), isFalse, reason: text);
    }

    // And with a server failure showing.
    await tester.enterText(find.byType(TextField), 'أرجو التواصل مع المتبرع');
    await tester.tap(find.byKey(_submit));
    await _settle(tester);
    expect(
      find.textContaining(ar['error_connect_request_submit_failed']!),
      findsOneWidget,
    );
    for (final text in _sheetTexts(tester)) {
      expect(latin.hasMatch(text), isFalse, reason: text);
    }
    await _close(tester);
  });
}
