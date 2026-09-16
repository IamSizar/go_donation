// Pins the "our team" wording of the connect-request button and sheet —
// OPOS #26351.
//
// WHY
// The Messages tab's chat-group sections, My Connect Requests and the chat
// lifecycle notices all call the people who review a request "our team"
// (فريقنا). The connect button and sheet called the same people "staff"
// (الفريق), so a member met two names for them inside one flow. The decision
// recorded on OPOS #26351 is "our team" everywhere a member reads it.
//
// WHAT IS PINNED, once in English and once in Arabic
//   1. The entry-point button's label.
//   2. The sheet's title, explainer and message hint.
//   3. The success view's body, shown in the sheet once the request is sent.
//   4. Nothing drawn on the button, the sheet or the success view says "staff"
//      (English) or الفريق (Arabic).
//
// The copy is written out in full here rather than read from the translation
// map: a test that looked the value up would pass whatever the value said.
// The toast for a member who closed the sheet before the answer arrived
// (`connect_request_sent`) is pinned in
// test/localization/chat_groups_our_team_copy_test.dart, which also scans every
// other chat-group and connect-request string.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/connect_request_button.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/connect_request_sheet.dart';

import 'fake_chat_groups_api.dart';

const _submit = Key('connect_request_submit');
const _contextId = 42;

/// What one locale must show on the button, the sheet and the success view.
class _OurTeamCopy {
  const _OurTeamCopy({
    required this.name,
    required this.locale,
    required this.action,
    required this.title,
    required this.explainer,
    required this.hint,
    required this.sentBody,
    required this.oldWord,
    required this.message,
  });

  /// The group name the tests run under.
  final String name;

  /// The locale the app is pumped in.
  final Locale locale;

  /// The entry-point button's label.
  final String action;

  /// The sheet's heading.
  final String title;

  /// The line under the heading saying what happens after sending.
  final String explainer;

  /// The message field's hint.
  final String hint;

  /// The success view's body.
  final String sentBody;

  /// The word for "staff" this locale must no longer show.
  final RegExp oldWord;

  /// A message the member types, in this locale.
  final String message;
}

final _copies = [
  _OurTeamCopy(
    name: 'English',
    locale: const Locale('en', 'US'),
    action: 'Ask our team to connect me',
    title: 'Ask our team to connect you',
    explainer:
        'Our team will review your request. If they approve it, they will '
        'open a supervised chat for you here in the app.',
    hint: 'Tell our team what you would like to discuss, and why.',
    sentBody:
        'Our team will review it shortly. You can follow it in My Connect '
        'Requests on the Messages tab.',
    oldWord: RegExp(r'\bstaff\b', caseSensitive: false),
    message: 'Please connect me.',
  ),
  _OurTeamCopy(
    name: 'Arabic',
    locale: const Locale('ar', 'SA'),
    action: 'اطلب التواصل عبر فريقنا',
    title: 'طلب تواصل عبر فريقنا',
    explainer:
        'سيراجع فريقنا طلبك، وإذا وافق عليه فسيفتح لك محادثة خاضعة للإشراف '
        'هنا في التطبيق.',
    hint: 'أخبر فريقنا بما تود مناقشته، ولماذا.',
    sentBody:
        'سيراجعه فريقنا قريبًا. يمكنك متابعته من «طلبات التواصل الخاصة بي» '
        'في تبويب «الرسائل».',
    oldWord: RegExp('الفريق'),
    message: 'أرجو التواصل مع المتبرع',
  ),
];

/// Pumps in short steps: long enough for a sheet to animate and the fake to
/// answer, without settling on a looping spinner.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps the entry-point button for donation [_contextId] in [locale].
Future<void> _pumpButton(WidgetTester tester, Locale locale) async {
  Get.locale = locale;
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      translations: AppTranslations(),
      locale: locale,
      home: Scaffold(
        body: Center(
          child: ConnectRequestButton(
            contextType: kConnectContextDonation,
            contextId: _contextId,
            api: FakeChatGroupsApi(),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// Opens the sheet the way a member does: by tapping the button.
Future<void> _openSheet(WidgetTester tester, Locale locale) async {
  await _pumpButton(tester, locale);
  await tester.tap(find.byType(ConnectRequestButton));
  await _settle(tester);
}

/// Disposes the tree before the test ends.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// The message field's hint. It is drawn only while the field is focused and
/// empty, so it is read from the decoration rather than found on screen.
String? _hint(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).decoration?.hintText;

/// Every string drawn on screen, plus the message field's hint when the field
/// is showing.
List<String> _drawnCopy(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
  if (find.byType(TextField).evaluate().isNotEmpty) _hint(tester) ?? '',
];

/// Fails when anything drawn still uses [copy]'s old word for staff.
void _expectNoOldWord(WidgetTester tester, _OurTeamCopy copy) {
  for (final text in _drawnCopy(tester)) {
    expect(copy.oldWord.hasMatch(text), isFalse, reason: text);
  }
}

void main() {
  setUp(() async {
    // isGuestMode() reads preferences; a guest would see no button at all.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
  });

  tearDown(Get.reset);

  for (final copy in _copies) {
    group(copy.name, () {
      testWidgets('the button asks our team to connect the member', (
        tester,
      ) async {
        await _pumpButton(tester, copy.locale);

        expect(find.text(copy.action), findsOneWidget);
        _expectNoOldWord(tester, copy);
        await _close(tester);
      });

      testWidgets('the sheet says our team reviews the request', (
        tester,
      ) async {
        await _openSheet(tester, copy.locale);

        expect(find.byType(ConnectRequestSheet), findsOneWidget);
        expect(find.text(copy.title), findsOneWidget);
        expect(find.text(copy.explainer), findsOneWidget);
        expect(_hint(tester), copy.hint);
        _expectNoOldWord(tester, copy);
        await _close(tester);
      });

      testWidgets('the success view says our team will review it', (
        tester,
      ) async {
        await _openSheet(tester, copy.locale);
        await tester.enterText(find.byType(TextField), copy.message);
        // A frame for the button to enable for the typed text.
        await tester.pump();
        await tester.tap(find.byKey(_submit));
        await _settle(tester);

        expect(find.byType(TextField), findsNothing);
        expect(find.text(copy.sentBody), findsOneWidget);
        _expectNoOldWord(tester, copy);
        await _close(tester);
      });
    });
  }
}
