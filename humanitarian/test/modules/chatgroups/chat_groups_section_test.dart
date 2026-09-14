// Pins ChatGroupsSection — the Messages tab's block for staff-mediated group
// chats, OPOS #25284 Phase 5 Task 4.
//
// WHAT IS PINNED
//   1. "My Connect Requests" is a standing door: it shows when the member has
//      no groups at all, and it opens MyConnectRequestsScreen.
//   2. No groups means no group sub-sections — most members have none, so an
//      empty heading would only be noise.
//   3. Masked groups sit under "My Connections" and are always titled
//      "Connection" — never a server-sent title, which could carry a name.
//      Team groups sit under "My Team Groups" with their own title, or a
//      fallback when it is blank.
//   4. The unread badge appears only when something is unread, and says so to
//      a screen reader.
//   5. Tapping a group opens its conversation under the same title, and
//      coming back refreshes the groups at once, so the unread badge the
//      member just read does not linger until the next 5-second poll.
//   6. A failed load shows Retry INSIDE the block and Retry recovers; a failed
//      refresh keeps groups that already loaded readable — and lays out
//      without error inside the Messages tab's ListView.
//   7. Arabic: nothing the block writes itself is in English.
//   8. A group tile is announced to screen readers as a button.
//   9. What people wrote — a last message, a team's title — is laid out in its
//      own direction, not the screen's: English on an Arabic screen keeps its
//      full stop at the end.
//
// The block no longer creates ChatGroupsController; MessagesScreen does (see
// messages_screen_chat_groups_wiring_test.dart). So [_open] registers one on
// the fake API first, exactly as Messages would.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chatgroups/controllers/chat_groups_controller.dart';
import 'package:flutter_application_1/modules/chatgroups/screens/chat_group_conversation_screen.dart';
import 'package:flutter_application_1/modules/chatgroups/screens/my_connect_requests_screen.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/chat_groups_section.dart';

import 'fake_chat_groups_api.dart';

final _en = AppTranslations.englishForTest;
final _ar = AppTranslations.arabicForTest;

/// Lets the fake API answer, the frames build and a route transition finish.
/// Short steps, so no 3- or 5-second poll ever fires inside a test.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Mounts the section the way the Messages tab does — one child of a ListView
/// inside a Scaffold, its controller registered by the screen's build just
/// before — and waits for its opening load.
///
/// The controller is put inside the tree rather than before pumpWidget: its
/// first load starts at once, and a failure message built before
/// GetMaterialApp has loaded the translations would come out untranslated.
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
      home: Builder(
        builder: (context) {
          if (!Get.isRegistered<ChatGroupsController>()) {
            Get.put(ChatGroupsController(api: api));
          }
          return Scaffold(
            body: ListView(children: [ChatGroupsSection(api: api)]),
          );
        },
      ),
    ),
  );
  await _settle(tester);
}

/// Unmounts everything and closes the groups controller, so its 5-second poll
/// is cancelled before the test ends.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await Get.delete<ChatGroupsController>(force: true);
  await tester.pump();
}

/// The vertical position of the first widget showing [text].
double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

/// The direction the paragraph showing [text] is laid out in.
TextDirection _directionOf(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).textDirection;

void main() {
  setUp(() async {
    // The new-group chime reads the global mute preference.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
  });

  tearDown(Get.reset);

  group('the connect-requests door', () {
    testWidgets('no groups: no group sub-sections, but the door stays', (
      tester,
    ) async {
      await _open(tester, FakeChatGroupsApi());

      expect(find.text(_en['chat_groups_my_connect_requests']!), findsOneWidget);
      expect(find.text(_en['chat_groups_my_connections']!), findsNothing);
      expect(find.text(_en['chat_groups_my_team_groups']!), findsNothing);
      await _close(tester);
    });

    testWidgets('it opens My Connect Requests on the same api', (tester) async {
      final api = FakeChatGroupsApi();
      await _open(tester, api);

      await tester.tap(find.text(_en['chat_groups_my_connect_requests']!));
      await _settle(tester);

      expect(find.byType(MyConnectRequestsScreen), findsOneWidget);
      expect(api.requestsCalls, 1);
      await _close(tester);
    });
  });

  testWidgets('masked and team groups sit in their own sub-sections', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..groups = [
        groupRow(id: 1, kind: 'masked', lastMessage: 'Thank you so much'),
        groupRow(id: 2, kind: 'team', title: 'Distribution team'),
        groupRow(id: 3, kind: 'masked'),
        groupRow(id: 4, kind: 'team'),
        // A masked group must never show a title, even if one arrives.
        groupRow(id: 5, kind: 'masked', title: 'Leaked real name'),
      ];

    await _open(tester, api);

    final connections = _en['chat_groups_my_connections']!;
    final teams = _en['chat_groups_my_team_groups']!;
    final connection = _en['chat_groups_connection_title']!;
    expect(find.text(connections), findsOneWidget);
    expect(find.text('(3)'), findsOneWidget);
    expect(find.text(teams), findsOneWidget);
    expect(find.text('(2)'), findsOneWidget);
    expect(find.text(connection), findsNWidgets(3));
    expect(find.text('Leaked real name'), findsNothing);
    expect(find.text('Distribution team'), findsOneWidget);
    expect(find.text(_en['chat_groups_team_group_title']!), findsOneWidget);
    expect(find.text('Thank you so much'), findsOneWidget);
    expect(find.text(_en['chat_groups_no_messages_yet']!), findsNWidgets(4));

    // Every masked tile sits between the two headings; team tiles below both.
    for (final element in find.text(connection).evaluate()) {
      final dy = tester.getTopLeft(find.byWidget(element.widget)).dy;
      expect(dy, greaterThan(_top(tester, connections)));
      expect(dy, lessThan(_top(tester, teams)));
    }
    expect(_top(tester, 'Distribution team'), greaterThan(_top(tester, teams)));
    await _close(tester);
  });

  testWidgets('the unread badge shows only when something is unread', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..groups = [
        groupRow(id: 1, kind: 'masked', unreadCount: 3),
        groupRow(id: 2, kind: 'team', title: 'Field team'),
      ];

    await _open(tester, api);

    final badge = find.byKey(const ValueKey('chat_group_unread_1'));
    expect(badge, findsOneWidget);
    expect(find.descendant(of: badge, matching: find.text('3')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_group_unread_2')), findsNothing);
    final spoken = _en['chat_groups_unread_count']!.replaceAll('@count', '3');
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == spoken,
      ),
      findsOneWidget,
    );
    await _close(tester);
  });

  group('tapping a group opens its conversation', () {
    testWidgets('a team group, under its own title', (tester) async {
      final api = FakeChatGroupsApi()
        ..groups = [groupRow(id: 8, kind: 'team', title: 'Field team')];
      await _open(tester, api);

      await tester.tap(find.text('Field team'));
      await _settle(tester);

      final screen = tester.widget<ChatGroupConversationScreen>(
        find.byType(ChatGroupConversationScreen),
      );
      expect(screen.groupId, 8);
      expect(screen.title, 'Field team');
      expect(screen.api, same(api));
      await _close(tester);
    });

    testWidgets('a masked group, as "Connection"', (tester) async {
      final api = FakeChatGroupsApi()
        ..groups = [groupRow(id: 7, kind: 'masked')];
      await _open(tester, api);

      await tester.tap(find.text(_en['chat_groups_connection_title']!));
      await _settle(tester);

      final screen = tester.widget<ChatGroupConversationScreen>(
        find.byType(ChatGroupConversationScreen),
      );
      expect(screen.groupId, 7);
      expect(screen.title, _en['chat_groups_connection_title']);
      await _close(tester);
    });

    testWidgets('coming back refreshes the groups, so a read badge clears', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..groups = [
          groupRow(id: 8, kind: 'team', title: 'Field team', unreadCount: 3),
        ];
      await _open(tester, api);
      final badge = find.byKey(const ValueKey('chat_group_unread_8'));
      expect(badge, findsOneWidget);

      await tester.tap(find.text('Field team'));
      await _settle(tester);
      // Reading the conversation cleared its unread count on the server.
      api.groups = [groupRow(id: 8, kind: 'team', title: 'Field team')];
      final callsBefore = api.groupsCalls;
      Get.back();
      await _settle(tester);

      expect(api.groupsCalls, callsBefore + 1);
      expect(badge, findsNothing);
      await _close(tester);
    });
  });

  testWidgets('a group tile is announced as one button', (tester) async {
    final semantics = tester.ensureSemantics();
    final api = FakeChatGroupsApi()
      ..groups = [
        groupRow(
          id: 8,
          kind: 'team',
          title: 'Field team',
          lastMessage: 'See you at nine',
          unreadCount: 2,
        ),
      ];
    await _open(tester, api);

    final tile = tester.getSemantics(find.text('Field team'));
    expect(tile, isSemantics(isButton: true, hasTapAction: true));
    // One announcement for the row: title, last message and unread count.
    expect(tile.label, contains('Field team'));
    expect(tile.label, contains('See you at nine'));
    expect(
      tile.label,
      contains(_en['chat_groups_unread_count']!.replaceAll('@count', '2')),
    );
    await _close(tester);
    semantics.dispose();
  });

  group('what people wrote keeps its own direction', () {
    testWidgets('English on an Arabic screen is laid out left-to-right', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..groups = [
          groupRow(
            id: 2,
            kind: 'team',
            title: 'Field team',
            lastMessage: 'God bless you all.',
          ),
        ];
      await _open(tester, api, locale: const Locale('ar', 'SA'));

      expect(_directionOf(tester, 'Field team'), TextDirection.ltr);
      expect(_directionOf(tester, 'God bless you all.'), TextDirection.ltr);
      await _close(tester);
    });

    testWidgets('Arabic on an English screen is laid out right-to-left', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..groups = [
          groupRow(
            id: 2,
            kind: 'team',
            title: 'فريق التوزيع',
            lastMessage: 'بارك الله فيكم.',
          ),
        ];
      await _open(tester, api);

      expect(_directionOf(tester, 'فريق التوزيع'), TextDirection.rtl);
      expect(_directionOf(tester, 'بارك الله فيكم.'), TextDirection.rtl);
      await _close(tester);
    });
  });

  group('failures', () {
    testWidgets('a failed load shows Retry inside the block; Retry recovers', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..groupsError = const SocketException('no route to host');
      await _open(tester, api);

      final retry = find.descendant(
        of: find.byType(ChatGroupsSection),
        matching: find.text(_en['retry']!),
      );
      expect(
        find.textContaining(_en['error_chat_groups_load_failed']!),
        findsOneWidget,
      );
      expect(retry, findsOneWidget);
      expect(find.text(_en['chat_groups_my_connect_requests']!), findsOneWidget);

      api
        ..groupsError = null
        ..groups = [groupRow(id: 1, kind: 'team', title: 'Field team')];
      await tester.tap(retry);
      await _settle(tester);

      expect(find.text('Field team'), findsOneWidget);
      expect(find.text(_en['retry']!), findsNothing);
      await _close(tester);
    });

    testWidgets('a failed refresh keeps loaded groups readable', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..groups = [groupRow(id: 1, kind: 'team', title: 'Field team')];
      await _open(tester, api);

      api.groupsError = const SocketException('no route to host');
      // A visible load, exactly as the Retry button starts one.
      Get.find<ChatGroupsController>().fetchGroups();
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(_en['error_chat_groups_load_failed']!),
        findsOneWidget,
      );
      expect(find.text('Field team'), findsOneWidget);
      await _close(tester);
    });
  });

  testWidgets('in Arabic the block writes no English', (tester) async {
    final api = FakeChatGroupsApi()
      ..groups = [
        groupRow(id: 1, kind: 'masked', unreadCount: 2),
        groupRow(id: 2, kind: 'team'),
      ];

    await _open(tester, api, locale: const Locale('ar', 'SA'));

    expect(find.text(_ar['chat_groups_my_connections']!), findsOneWidget);
    final texts = find
        .descendant(
          of: find.byType(ChatGroupsSection),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .where((t) => t.trim().isNotEmpty)
        .toList();
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(
        RegExp('[A-Za-z]').hasMatch(text),
        isFalse,
        reason: 'English leaked onto the Arabic Messages tab: "$text"',
      );
    }
    await _close(tester);
  });
}
