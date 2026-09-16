// Pins MyConnectRequestsScreen — the requester's own history of "ask staff to
// connect me" requests, OPOS #25284 Phase 5 Task 4.
//
// WHAT IS PINNED
//   1. Each request shows its status chip in the theme's colour for that
//      status (never a hard-coded red), what it is about, the member's own
//      message and the date; a declined one also shows staff's reason.
//   2. An APPROVED request with a group opens that group — the link the old
//      plan's code forgot. A pending request opens nothing, and neither does
//      an approved row with no group id, which the server never sends
//      (approval creates the group in the same transaction) but which must not
//      crash. The conversation opens under the group's own title when the
//      Messages tab has it loaded — a team's name, or "Connection" for a
//      masked group — and coming back refreshes that tab's groups at once.
//   3. The designed empty state, and a failed load shown as an error with
//      Retry that recovers.
//   4. Pull-to-refresh really refreshes — on the list and on the empty state —
//      and a failed refresh keeps the requests already on screen readable.
//   5. Arabic: no English on the screen, the date in Arabic, and the status
//      chip at the reading start — the right.
//   6. An openable request is announced to screen readers as a button.
//   7. What people wrote — the member's message, staff's decline reason — is
//      laid out in its own direction, not the screen's.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
// intl has a TextDirection of its own, which would shadow Flutter's.
import 'package:intl/intl.dart' hide TextDirection;

import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chatgroups/controllers/chat_groups_controller.dart';
import 'package:flutter_application_1/modules/chatgroups/screens/chat_group_conversation_screen.dart';
import 'package:flutter_application_1/modules/chatgroups/screens/my_connect_requests_screen.dart';

import 'fake_chat_groups_api.dart';

final _en = AppTranslations.englishForTest;
final _ar = AppTranslations.arabicForTest;

/// The `created_at` every `connectRequestRow` carries.
final _createdAt = DateTime.parse('2026-09-14T10:00:00Z');

/// Lets the fake API answer, the frames build and a route transition finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Opens the screen on [api] and waits for its opening load.
Future<void> _open(
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
      home: MyConnectRequestsScreen(api: api),
    ),
  );
  await _settle(tester);
}

/// Leaves the screen, disposing it and any conversation opened from it — the
/// conversation's poll included — and deletes the groups controller a test
/// registered, cancelling its poll too, before the test ends.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  if (Get.isRegistered<ChatGroupsController>()) {
    await Get.delete<ChatGroupsController>(force: true);
  }
  await tester.pump();
}

/// Registers the Messages tab's groups controller on [api]. This screen is
/// only reachable from Messages, where that controller always exists.
void _registerGroups(FakeChatGroupsApi api) {
  Get.put(ChatGroupsController(api: api));
}

/// Taps the request showing [message], reads the title its conversation
/// opened under, then comes back.
Future<String> _titleOpenedFrom(WidgetTester tester, String message) async {
  await tester.ensureVisible(find.text(message));
  await tester.tap(find.text(message));
  await _settle(tester);
  final title = tester
      .widget<ChatGroupConversationScreen>(
        find.byType(ChatGroupConversationScreen),
      )
      .title;
  Get.back();
  await _settle(tester);
  return title;
}

/// The direction the paragraph showing [text] is laid out in.
TextDirection _directionOf(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).textDirection;

/// The colour the status chip's label is drawn in.
Color? _inkOf(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

void main() {
  setUpAll(() async {
    // The app loads Arabic calendar data at startup (AppLocaleService.
    // syncDateFormatLocale); a test has to do the same before asking for it.
    await initializeDateFormatting('ar');
  });

  setUp(Get.reset);

  tearDown(() {
    Intl.defaultLocale = null;
    Get.reset();
  });

  testWidgets('each request shows status, subject, message, date and reason', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..requests = [
        connectRequestRow(
          id: 3,
          status: 'pending',
          contextType: 'case',
          message: 'Can someone help with the rent?',
        ),
        connectRequestRow(
          id: 2,
          status: 'approved',
          groupId: 31,
          message: 'I would like to thank the family',
        ),
        connectRequestRow(
          id: 1,
          status: 'declined',
          message: 'Please share their phone number',
          declineReason: 'We cannot share contact details.',
        ),
      ];

    await _open(tester, api);

    final pending = _en['chat_groups_status_pending']!;
    final approved = _en['chat_groups_status_approved']!;
    final declined = _en['chat_groups_status_declined']!;
    expect(find.text(pending), findsOneWidget);
    expect(find.text(approved), findsOneWidget);
    expect(find.text(declined), findsOneWidget);
    // Theme colours per status — declined is the consequence colour.
    expect(_inkOf(tester, pending), AppColors.light.pending);
    expect(_inkOf(tester, approved), AppColors.light.accent);
    expect(_inkOf(tester, declined), AppColors.light.consequence);

    expect(find.text(_en['chat_groups_about_case']!), findsOneWidget);
    expect(find.text(_en['chat_groups_about_donation']!), findsNWidgets(2));
    expect(find.text('Can someone help with the rent?'), findsOneWidget);
    expect(find.text('I would like to thank the family'), findsOneWidget);
    expect(
      find.text(DateFormat.yMMMd().format(_createdAt.toLocal())),
      findsNWidgets(3),
    );

    // Only the declined request carries a reason.
    expect(find.text(_en['chat_groups_decline_reason_label']!), findsOneWidget);
    expect(find.text('We cannot share contact details.'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('an approved request opens its group; others open nothing', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..requests = [
        connectRequestRow(id: 3, status: 'pending', message: 'Pending one'),
        connectRequestRow(id: 4, status: 'approved', message: 'No group yet'),
        connectRequestRow(
          id: 2,
          status: 'approved',
          groupId: 31,
          message: 'Approved one',
        ),
      ];
    await _open(tester, api);

    await tester.tap(find.text('Pending one'), warnIfMissed: false);
    await tester.tap(find.text('No group yet'), warnIfMissed: false);
    await _settle(tester);
    expect(find.byType(ChatGroupConversationScreen), findsNothing);

    await tester.tap(find.text('Approved one'));
    await _settle(tester);

    final screen = tester.widget<ChatGroupConversationScreen>(
      find.byType(ChatGroupConversationScreen),
    );
    expect(screen.groupId, 31);
    expect(screen.title, _en['chat_groups_connection_title']);
    expect(screen.api, same(api));
    await _close(tester);
  });

  group("with the Messages tab's groups loaded", () {
    testWidgets("an approved request opens under its group's own title", (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..groups = [
          groupRow(id: 31, kind: 'team', title: 'Field team'),
          groupRow(id: 32, kind: 'team'),
          groupRow(id: 33, kind: 'masked', title: 'Leaked real name'),
        ]
        ..requests = [
          connectRequestRow(
            id: 1,
            status: 'approved',
            groupId: 31,
            message: 'Team one',
          ),
          connectRequestRow(
            id: 2,
            status: 'approved',
            groupId: 32,
            message: 'Untitled team',
          ),
          connectRequestRow(
            id: 3,
            status: 'approved',
            groupId: 33,
            message: 'Masked one',
          ),
          connectRequestRow(
            id: 4,
            status: 'approved',
            groupId: 99,
            message: 'Not loaded',
          ),
        ];
      _registerGroups(api);
      await _open(tester, api);

      final connection = _en['chat_groups_connection_title'];
      expect(await _titleOpenedFrom(tester, 'Team one'), 'Field team');
      expect(
        await _titleOpenedFrom(tester, 'Untitled team'),
        _en['chat_groups_team_group_title'],
      );
      expect(await _titleOpenedFrom(tester, 'Masked one'), connection);
      // Not in the tab's list yet: the neutral title that names no one.
      expect(await _titleOpenedFrom(tester, 'Not loaded'), connection);
      await _close(tester);
    });

    testWidgets('coming back from the conversation refreshes the groups', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..groups = [groupRow(id: 31, kind: 'team', title: 'Field team')]
        ..requests = [
          connectRequestRow(
            id: 2,
            status: 'approved',
            groupId: 31,
            message: 'Approved one',
          ),
        ];
      _registerGroups(api);
      await _open(tester, api);
      final callsBefore = api.groupsCalls;

      await _titleOpenedFrom(tester, 'Approved one');

      expect(api.groupsCalls, callsBefore + 1);
      await _close(tester);
    });
  });

  testWidgets('an openable request is announced as a button; others are not', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final api = FakeChatGroupsApi()
      ..requests = [
        connectRequestRow(id: 3, status: 'pending', message: 'Pending one'),
        connectRequestRow(
          id: 2,
          status: 'approved',
          groupId: 31,
          message: 'Approved one',
        ),
      ];
    await _open(tester, api);

    final approved = tester.getSemantics(find.text('Approved one'));
    expect(approved, isSemantics(isButton: true, hasTapAction: true));
    expect(approved.label, contains('Approved one'));
    expect(approved.label, contains(_en['chat_groups_open_conversation']!));
    expect(
      tester.getSemantics(find.text('Pending one')),
      isSemantics(isButton: false, hasTapAction: false),
    );
    await _close(tester);
    semantics.dispose();
  });

  group('what people wrote keeps its own direction', () {
    testWidgets('English on an Arabic screen is laid out left-to-right', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..requests = [
          connectRequestRow(
            id: 1,
            status: 'declined',
            message: 'I will bring the van.',
            declineReason: 'We cannot share contact details.',
          ),
        ];
      await _open(tester, api, locale: const Locale('ar', 'SA'));

      expect(_directionOf(tester, 'I will bring the van.'), TextDirection.ltr);
      expect(
        _directionOf(tester, 'We cannot share contact details.'),
        TextDirection.ltr,
      );
      await _close(tester);
    });

    testWidgets('Arabic on an English screen is laid out right-to-left', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..requests = [
          connectRequestRow(
            id: 1,
            status: 'declined',
            message: 'سأحضر الشاحنة.',
            declineReason: 'لا يمكننا مشاركة بيانات التواصل.',
          ),
        ];
      await _open(tester, api);

      expect(_directionOf(tester, 'سأحضر الشاحنة.'), TextDirection.rtl);
      expect(
        _directionOf(tester, 'لا يمكننا مشاركة بيانات التواصل.'),
        TextDirection.rtl,
      );
      await _close(tester);
    });
  });

  testWidgets('no requests shows the designed empty state, which refreshes', (
    tester,
  ) async {
    final api = FakeChatGroupsApi();
    await _open(tester, api);

    final title = find.text(_en['chat_groups_requests_empty_title']!);
    expect(title, findsOneWidget);
    expect(
      find.text(_en['chat_groups_requests_empty_message']!),
      findsOneWidget,
    );

    await tester.fling(title, const Offset(0, 300), 1000);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(api.requestsCalls, 2);
    await _close(tester);
  });

  testWidgets('a failed load shows an error with Retry, and Retry recovers', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..requestsError = const SocketException('no route to host');
    await _open(tester, api);

    expect(
      find.textContaining(_en['error_connect_requests_load_failed']!),
      findsOneWidget,
    );
    expect(find.text(_en['chat_groups_requests_empty_title']!), findsNothing);

    api
      ..requestsError = null
      ..requests = [connectRequestRow(id: 1, status: 'pending', message: 'Hi')];
    await tester.tap(find.text(_en['retry']!));
    await _settle(tester);

    expect(find.text('Hi'), findsOneWidget);
    expect(find.text(_en['retry']!), findsNothing);
    await _close(tester);
  });

  testWidgets('pulling down refreshes; a failed refresh keeps what was shown', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..requests = [connectRequestRow(id: 1, status: 'pending', message: 'Hi')];
    await _open(tester, api);
    expect(api.requestsCalls, 1);

    api.requestsError = const SocketException('no route to host');
    await tester.fling(find.text('Hi'), const Offset(0, 300), 1000);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(api.requestsCalls, 2);
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining(_en['error_connect_requests_load_failed']!),
      findsOneWidget,
    );
    expect(find.text('Hi'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('in Arabic: no English, an Arabic date, the chip at the right', (
    tester,
  ) async {
    // What AppLocaleService.syncDateFormatLocale does when Arabic is chosen.
    Intl.defaultLocale = 'ar';
    final api = FakeChatGroupsApi()
      ..requests = [
        connectRequestRow(
          id: 1,
          status: 'declined',
          contextType: 'case',
          message: 'أرجو التواصل مع الأسرة',
          declineReason: 'لا يمكننا مشاركة بيانات التواصل.',
        ),
        connectRequestRow(
          id: 2,
          status: 'approved',
          groupId: 9,
          message: 'شكراً لكم',
        ),
        connectRequestRow(id: 3, status: 'pending', message: 'أود المساعدة'),
      ];

    await _open(tester, api, locale: const Locale('ar', 'SA'));

    final texts = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .where((t) => t.trim().isNotEmpty)
        .toList();
    expect(texts, contains(_ar['chat_groups_my_connect_requests']));
    for (final text in texts) {
      expect(
        RegExp('[A-Za-z]').hasMatch(text),
        isFalse,
        reason: 'English leaked onto the Arabic requests screen: "$text"',
      );
    }

    final date = find.text(DateFormat.yMMMd().format(_createdAt.toLocal()));
    expect(date, findsNWidgets(3));
    final chip = find.text(_ar['chat_groups_status_pending']!);
    expect(
      tester.getCenter(chip).dx,
      greaterThan(tester.getCenter(date.first).dx),
      reason: 'right-to-left: the status leads the row, so it sits on the right',
    );
    await _close(tester);
  });
}
