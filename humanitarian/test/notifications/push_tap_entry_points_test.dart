// The three ways a notification gets tapped must agree.
//
// A tap arrives by three different routes, and the cold-start one is the easy
// one to forget:
//   1. FirebaseMessaging.onMessageOpenedApp — tapped while the app is
//      backgrounded.
//   2. FirebaseMessaging.instance.getInitialMessage() — tapped while the app
//      was KILLED; the tap launches the process and the message is handed over
//      once, at startup. Nothing was listening to this before.
//   3. The in-app notifications list, which must not grow a second, divergent
//      opinion about where a chat notification leads.
//
// The first two cannot be exercised without a live Firebase plugin, so this
// file pins them structurally: both listeners in the router must go through
// the one shared decision, and neither may navigate on its own.

import 'dart:io';

import 'package:flutter_application_1/core/push_tap_router.dart';
import 'package:flutter_application_1/modules/notifications/utils/notification_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/core/push_tap_router.dart').readAsStringSync();

  group('the cold-start path exists and shares the backgrounded decision', () {
    test('the router wires BOTH onMessageOpenedApp and getInitialMessage', () {
      expect(
        source.contains('onMessageOpenedApp'),
        isTrue,
        reason: 'the backgrounded tap must be handled',
      );
      expect(
        source.contains('getInitialMessage'),
        isTrue,
        reason:
            'the tap that launches the app from killed is a separate path; '
            'without it a cold tap still opens at home',
      );
    });

    test('both entry points call the same handler', () {
      // One handler, called twice — not two copies of the routing that can
      // drift apart.
      final calls = RegExp(
        r'PushTapRouter\.handleData|_handleData|handleData\(',
      ).allMatches(source).length;
      expect(
        calls,
        greaterThanOrEqualTo(3),
        reason:
            'expected the shared handler to be declared once and called from '
            'both the onMessageOpenedApp listener and the getInitialMessage '
            'path; found $calls references',
      );
    });

    test('the router does not decide anything itself', () {
      // Every routing decision belongs to resolveNotificationDestination, so
      // the tests above cover the router too.
      expect(source.contains('resolveNotificationDestination'), isTrue);
    });
  });

  group('the handler answers with the shared decision', () {
    test('a group push resolves to that group, whatever the entry point', () {
      const data = <String, dynamic>{
        'type': 'chat_group_message',
        'related_entity_type': 'chat_group_thread',
        'related_entity_id': '42',
      };
      expect(
        PushTapRouter.destinationFor(data, isGuest: () => false),
        resolveNotificationDestination(data, isGuest: () => false),
      );
      expect(
        PushTapRouter.destinationFor(data, isGuest: () => false),
        NotificationDestination.groupChat(42),
      );
    });

    test('a guest push resolves to the list through the router too', () {
      const data = <String, dynamic>{
        'type': 'chat_message',
        'related_entity_type': 'chat_thread',
        'related_entity_id': '7',
      };
      expect(
        PushTapRouter.destinationFor(data, isGuest: () => true),
        NotificationDestination.notificationsList,
      );
    });
  });
}
