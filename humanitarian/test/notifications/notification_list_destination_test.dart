// The in-app notifications list uses the same decision as a tapped push.
//
// NotificationsController.destinationFor already knew about support tickets,
// media posts and partners — and returned null for every chat notification, so
// tapping "New message in <group>" in the list did nothing. The push routing
// added for the client's report answers exactly that question, so the list
// asks it too rather than growing a second opinion.
//
// destinationFor returns a VoidCallback, so what is asserted here is "has
// somewhere to go" / "has nowhere to go" — WHERE it goes is pinned, by value,
// in notification_destination_test.dart.

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/notifications/models/app_notification_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppNotificationModel chatNotification({
  required String type,
  required String entityType,
  String entityId = '42',
}) {
  return AppNotificationModel(
    id: '1',
    title: 'Title',
    titleAr: '',
    titleSorani: '',
    titleBadini: '',
    message: 'Body',
    messageAr: '',
    messageSorani: '',
    messageBadini: '',
    notificationType: type,
    notificationCategory: 'normal',
    priority: 0,
    isRead: false,
    createdAt: DateTime(2026, 9, 16),
    relatedEntityType: entityType,
    relatedEntityId: entityId,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationsController controller;

  Future<void> useSession({required bool asGuest}) async {
    SharedPreferences.setMockInitialValues({
      'id_user': '7',
      kGuestModePrefsKey: asGuest,
    });
    sharedPreferences = await SharedPreferences.getInstance();
  }

  setUp(() async {
    await useSession(asGuest: false);
    controller = NotificationsController();
  });

  test('a group message in the list is no longer a dead tap', () {
    expect(
      controller.destinationFor(
        chatNotification(
          type: 'chat_group_message',
          entityType: 'chat_group_thread',
        ),
      ),
      isNotNull,
    );
  });

  test('a direct/support message in the list opens something', () {
    expect(
      controller.destinationFor(
        chatNotification(type: 'chat_message', entityType: 'chat_thread'),
      ),
      isNotNull,
    );
  });

  test('a marriage message in the list opens something', () {
    expect(
      controller.destinationFor(
        chatNotification(
          type: 'marriage_chat_message',
          entityType: 'marriage_chat_thread',
        ),
      ),
      isNotNull,
    );
  });

  test('a chat notification offers a GUEST nothing to open', () async {
    // Already on the notifications list, so the fallback destination is a
    // no-op there — and it must certainly not be a chat screen.
    await useSession(asGuest: true);
    expect(
      controller.destinationFor(
        chatNotification(type: 'chat_message', entityType: 'chat_thread'),
      ),
      isNull,
    );
  });

  test('a malformed id still opens nothing from the list', () {
    expect(
      controller.destinationFor(
        chatNotification(
          type: 'chat_message',
          entityType: 'chat_thread',
          entityId: 'not-an-id',
        ),
      ),
      isNull,
    );
  });

  test('a type with no screen behind it is still left alone', () {
    // Guards the existing contract in support_destination_test.dart: the new
    // chat branch must not start claiming everything.
    expect(
      controller.destinationFor(
        chatNotification(type: 'wallet_topup', entityType: ''),
      ),
      isNull,
    );
  });
}
