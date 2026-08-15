// Where a tapped notification leads.
//
// The support notifications were a dead end twice over. `destinationFor`
// matched the exact string 'support_ticket', but the backend never emits that:
// it emits `support_request_submitted`, `support_ticket_<status>` (open,
// in_progress, resolved, closed) and `support_ticket_replied`. So every
// support alert fell through to `null` and tapping it did nothing.
//
// And on the one path that could have matched, the destination was
// SupportTicketFormScreen — a blank compose box, not the ticket whose reply
// the user had just been told about. That screen is gone; the destination is
// now the real support screen, which shows the request history and the staff
// reply.
//
// This matters most for `support_ticket_replied`: the whole point of that
// notification is "an answer arrived, come and read it". A tap that goes
// nowhere makes the notification worse than none.

import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/notifications/models/app_notification_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a notification carrying only the fields this test cares about.
AppNotificationModel notificationOfType(String type, {String actionUrl = ''}) {
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
    notificationCategory: 'support',
    priority: 1,
    isRead: false,
    createdAt: DateTime(2026, 8, 15),
    actionUrl: actionUrl,
  );
}

void main() {
  late NotificationsController controller;

  setUp(() {
    controller = NotificationsController();
  });

  group('destinationFor — support notifications', () {
    // Every type the backend actually emits for a support ticket. The old
    // exact match on 'support_ticket' caught NONE of these.
    const supportTypes = [
      'support_request_submitted',
      'support_ticket_open',
      'support_ticket_in_progress',
      'support_ticket_resolved',
      'support_ticket_closed',
      'support_ticket_replied',
    ];

    for (final type in supportTypes) {
      test('$type has somewhere to go', () {
        expect(
          controller.destinationFor(notificationOfType(type)),
          isNotNull,
          reason:
              '$type is a type the backend emits; a tap on it must not be a '
              'no-op',
        );
      });
    }

    test('a reply alert is actionable — that is the whole point of it', () {
      // The reply notification exists to say "an answer arrived, come and
      // read it". If it leads nowhere it is noise.
      expect(
        controller.destinationFor(
          notificationOfType('support_ticket_replied'),
        ),
        isNotNull,
      );
    });

    test('an unrelated type is still left alone', () {
      // The prefix check must not swallow everything: a type with no screen
      // behind it still returns null, so the UI can hide the Open action
      // rather than offer a button that does nothing.
      expect(
        controller.destinationFor(notificationOfType('wallet_topup')),
        isNull,
      );
    });

    test('an explicit action_url still wins over the type mapping', () {
      // A server-supplied deep link is more specific than our type guess, and
      // the prefix check must not have jumped the queue ahead of it.
      expect(
        controller.destinationFor(
          notificationOfType(
            'support_ticket_replied',
            actionUrl: 'https://example.org/tickets/9',
          ),
        ),
        isNotNull,
      );
    });
  });
}
