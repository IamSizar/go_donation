// notifications_read_and_clear_test.dart — a read notification leaves the
// list, and the list can be cleared.
//
// THE TWO REPORTS (client, 2026-09-16)
//   "marking a notification as read doesnt make it go away"
//   "old notifications must go away"
//
// WHAT WAS WRONG
// NotificationsController.selectedReadStatus started at 'all', so a row that
// had just been marked read stayed exactly where it was — only its styling
// changed. The swipe gesture made this worse: NotificationTile wraps the card
// in a Dismissible whose onDismissed only calls markAsRead, so the card slid
// away and the very next rebuild put it straight back.
//
// And nothing ever removed a notification. There was no clear/delete action in
// the app, no endpoint behind one, and no retention rule, so every row a user
// had ever received stayed in the list for good.
//
// WHAT IS PINNED HERE
//   • the default list shows unread only, so marking read removes the row;
//   • the Read chip is still the way to see what was read — nothing is hidden
//     with no way back;
//   • clearReadNotifications() takes the read rows out of the list and tells
//     the server, and puts them back when the server refuses.
//
// The server half — that a cleared row never comes back on the next poll, and
// that an old read row falls out on its own — is pinned in Go, in
// backend/internal/handlers/notifications_clear_test.go.

import 'dart:convert';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/notifications/models/app_notification_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One notification, read or unread, with everything else held constant so a
/// test only ever varies the thing it is about.
AppNotificationModel notification({required String id, required bool isRead}) {
  return AppNotificationModel(
    id: id,
    title: 'Title $id',
    titleAr: '',
    titleSorani: '',
    titleBadini: '',
    message: 'Body $id',
    messageAr: '',
    messageSorani: '',
    messageBadini: '',
    notificationType: 'system_test',
    notificationCategory: 'normal',
    priority: 0,
    isRead: isRead,
    createdAt: DateTime(2026, 9, 16),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'id_user': '7'});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  group('the list a volunteer opens', () {
    test('shows the unread notifications and not the read ones', () {
      final controller = NotificationsController()
        ..notifications.assignAll([
          notification(id: '1', isRead: false),
          notification(id: '2', isRead: true),
        ]);

      expect(
        controller.filteredNotifications.map((n) => n.id),
        ['1'],
        reason: 'a read notification must leave the list it was read in',
      );
    });

    test('shows the read ones again under the Read chip', () {
      final controller = NotificationsController()
        ..notifications.assignAll([
          notification(id: '1', isRead: false),
          notification(id: '2', isRead: true),
        ])
        ..setReadStatus('read');

      expect(controller.filteredNotifications.map((n) => n.id), ['2']);
    });

    test('shows both under the All chip', () {
      final controller = NotificationsController()
        ..notifications.assignAll([
          notification(id: '1', isRead: false),
          notification(id: '2', isRead: true),
        ])
        ..setReadStatus('all');

      expect(controller.filteredNotifications.map((n) => n.id), ['1', '2']);
    });
  });

  group('clearing the read notifications', () {
    test('removes them and asks the server to clear them', () async {
      final bodies = <Map<String, dynamic>>[];
      final controller =
          NotificationsController(
              api: ModuleApi(
                httpClient: MockClient((request) async {
                  bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
                  return http.Response('{"success":true,"cleared":2}', 200);
                }),
              ),
            )
            ..notifications.assignAll([
              notification(id: '1', isRead: false),
              notification(id: '2', isRead: true),
              notification(id: '3', isRead: true),
            ]);

      await controller.clearReadNotifications();

      expect(controller.notifications.map((n) => n.id), ['1']);
      expect(bodies.single['action'], 'clear_read');
      expect(bodies.single['user_id'], '7');
    });

    test('puts them back when the server refuses', () async {
      final controller =
          NotificationsController(
              api: ModuleApi(
                httpClient: MockClient(
                  (_) async => http.Response('{"success":false}', 500),
                ),
              ),
            )
            ..notifications.assignAll([
              notification(id: '1', isRead: false),
              notification(id: '2', isRead: true),
            ]);

      await controller.clearReadNotifications();

      expect(controller.notifications.map((n) => n.id), ['1', '2']);
      expect(controller.errorMessage.value, isNotNull);
    });

    test('is a no-op, and touches no network, when nothing is read', () async {
      var called = false;
      final controller = NotificationsController(
        api: ModuleApi(
          httpClient: MockClient((_) async {
            called = true;
            return http.Response('{"success":true}', 200);
          }),
        ),
      )..notifications.assignAll([notification(id: '1', isRead: false)]);

      await controller.clearReadNotifications();

      expect(called, isFalse);
      expect(controller.notifications.map((n) => n.id), ['1']);
    });
  });
}
