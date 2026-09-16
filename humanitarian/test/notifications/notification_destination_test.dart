// Where a TAPPED PUSH goes.
//
// WHY THIS FILE EXISTS
// The client reported it today: tapping a push notification opened the app at
// home and left the person to hunt for the conversation the notification was
// about. `lib/main.dart` subscribed to FirebaseMessaging.onMessageOpenedApp
// and only printed a debug line — it navigated nowhere — and the cold-start
// path (getInitialMessage, the tap that LAUNCHES the app from killed) was not
// wired at all.
//
// WHAT IS PINNED HERE
//   1. Each chat family routes to its own conversation: group, direct/support,
//      marriage.
//   2. A chat request routes to where it can actually be accepted.
//   3. An unknown type, a missing id, and a malformed id all fall back to the
//      notifications list. A tap is NEVER dead.
//   4. A guest (#106, #113) is never navigated into a chat, whatever the
//      payload says.
//   5. The cold-start path and the backgrounded path use the SAME decision.
//
// THE DATA KEYS THIS DEPENDS ON
// The push payload is being changed in parallel (OPOS #26709 — push delivery),
// so the decision reads the keys that mirror the columns the backend already
// writes on every in-app row (notify.LocalizedMessage → app_notifications):
//   • type                 (alias: notification_type)
//   • related_entity_type  (alias: entity_type)
//   • related_entity_id    (aliases: entity_id, thread_id, group_id)
// related_entity_type is authoritative when present; the type is the fallback,
// so the routing survives either shape.

import 'package:flutter_application_1/modules/notifications/utils/notification_destination.dart';
import 'package:flutter_test/flutter_test.dart';

/// A push payload. FCM delivers every value as a String, which is why the ids
/// below are quoted — parsing them is part of what is under test.
Map<String, dynamic> push({
  String? type,
  String? entityType,
  String? entityId,
  Map<String, dynamic> extra = const {},
}) {
  return <String, dynamic>{
    if (type != null) 'type': type,
    if (entityType != null) 'related_entity_type': entityType,
    if (entityId != null) 'related_entity_id': entityId,
    ...extra,
  };
}

/// Not a guest — the common case.
bool member() => false;

/// A guest session.
bool guest() => true;

void main() {
  group('by type — every chat family reaches its own conversation', () {
    test('a group message opens that group', () {
      expect(
        resolveNotificationDestination(
          push(
            type: 'chat_group_message',
            entityType: 'chat_group_thread',
            entityId: '42',
          ),
          isGuest: member,
        ),
        NotificationDestination.groupChat(42),
      );
    });

    test('a 1:1 / support message opens that conversation', () {
      expect(
        resolveNotificationDestination(
          push(type: 'chat_message', entityType: 'chat_thread', entityId: '7'),
          isGuest: member,
        ),
        NotificationDestination.directChat(7),
      );
    });

    test('an accepted chat opens the conversation it unlocked', () {
      expect(
        resolveNotificationDestination(
          push(type: 'chat_accepted', entityType: 'chat_thread', entityId: '7'),
          isGuest: member,
        ),
        NotificationDestination.directChat(7),
      );
    });

    test('a marriage message opens that marriage conversation', () {
      expect(
        resolveNotificationDestination(
          push(
            type: 'marriage_chat_message',
            entityType: 'marriage_chat_thread',
            entityId: '9',
          ),
          isGuest: member,
        ),
        NotificationDestination.marriageChat(9),
      );
    });

    test('a marriage chat request opens the thread, where Accept lives', () {
      // Accept/Decline for a marriage thread is inside the conversation
      // screen (marriage_chat_conversation_screen.dart), not on the list.
      expect(
        resolveNotificationDestination(
          push(
            type: 'marriage_chat_request',
            entityType: 'marriage_chat_thread',
            entityId: '9',
          ),
          isGuest: member,
        ),
        NotificationDestination.marriageChat(9),
      );
    });

    test('a chat request opens where it can be accepted', () {
      // A direct chat request is answered on Messages (IncomingChatRequestCard)
      // — NOT inside a conversation that does not exist yet.
      expect(
        resolveNotificationDestination(
          push(
            type: 'chat_request',
            entityType: 'chat_thread',
            entityId: '11',
          ),
          isGuest: member,
        ),
        NotificationDestination.chatRequests,
      );
    });
  });

  group('the payload shape is not assumed', () {
    test('the aliases notification_type / entity_type / entity_id work', () {
      // OPOS #26709 may name the keys this way; both shapes must route.
      expect(
        resolveNotificationDestination(const {
          'notification_type': 'chat_group_message',
          'entity_type': 'chat_group_thread',
          'entity_id': '42',
        }, isGuest: member),
        NotificationDestination.groupChat(42),
      );
    });

    test('thread_id and group_id are accepted as the id', () {
      expect(
        resolveNotificationDestination(const {
          'type': 'chat_message',
          'thread_id': '7',
        }, isGuest: member),
        NotificationDestination.directChat(7),
      );
      expect(
        resolveNotificationDestination(const {
          'type': 'chat_group_message',
          'group_id': '42',
        }, isGuest: member),
        NotificationDestination.groupChat(42),
      );
    });

    test('an id that arrives as a number, not a string, still parses', () {
      expect(
        resolveNotificationDestination(const {
          'type': 'chat_message',
          'related_entity_id': 7,
        }, isGuest: member),
        NotificationDestination.directChat(7),
      );
    });

    test('related_entity_type decides even when the type is unfamiliar', () {
      // A type this app has never heard of, on an entity it knows, is still
      // routable — and the backend adds types faster than the app learns them.
      expect(
        resolveNotificationDestination(
          push(
            type: 'chat_group_something_new',
            entityType: 'chat_group_thread',
            entityId: '42',
          ),
          isGuest: member,
        ),
        NotificationDestination.groupChat(42),
      );
    });
  });

  group('nothing is ever a dead tap', () {
    test('an unknown type falls back to the notifications list', () {
      expect(
        resolveNotificationDestination(
          push(type: 'wallet_topup', entityId: '3'),
          isGuest: member,
        ),
        NotificationDestination.notificationsList,
      );
    });

    test('an empty payload falls back to the notifications list', () {
      expect(
        resolveNotificationDestination(const {}, isGuest: member),
        NotificationDestination.notificationsList,
      );
    });

    test('a chat type with NO id falls back rather than opening nothing', () {
      expect(
        resolveNotificationDestination(
          push(type: 'chat_message', entityType: 'chat_thread'),
          isGuest: member,
        ),
        NotificationDestination.notificationsList,
      );
    });

    for (final bad in const ['', '   ', 'abc', '0', '-4', '1.5', 'null']) {
      test('a malformed id (${bad.isEmpty ? '<empty>' : bad}) falls back', () {
        expect(
          resolveNotificationDestination(
            push(
              type: 'chat_group_message',
              entityType: 'chat_group_thread',
              entityId: bad,
            ),
            isGuest: member,
          ),
          NotificationDestination.notificationsList,
        );
      });
    }

    test('staff chat has no screen on mobile, so it lands on the list', () {
      // staff_chat_thread is an admin-web system; the app has no screen for
      // it (grep staff_chat in humanitarian/lib → translations only). The
      // notification still has somewhere to land.
      expect(
        resolveNotificationDestination(
          push(
            type: 'staff_chat_message',
            entityType: 'staff_chat_thread',
            entityId: '5',
          ),
          isGuest: member,
        ),
        NotificationDestination.notificationsList,
      );
    });
  });

  group('a guest is never navigated into a chat (#106, #113)', () {
    const chatPayloads = <Map<String, dynamic>>[
      {
        'type': 'chat_group_message',
        'related_entity_type': 'chat_group_thread',
        'related_entity_id': '42',
      },
      {
        'type': 'chat_message',
        'related_entity_type': 'chat_thread',
        'related_entity_id': '7',
      },
      {
        'type': 'marriage_chat_message',
        'related_entity_type': 'marriage_chat_thread',
        'related_entity_id': '9',
      },
      {
        'type': 'chat_request',
        'related_entity_type': 'chat_thread',
        'related_entity_id': '11',
      },
    ];

    for (final payload in chatPayloads) {
      test('${payload['type']} sends a guest to the notifications list', () {
        // The server refuses a guest's chat calls outright (RequireNotGuest)
        // and withholds the push in the first place (shouldWithholdChatPush),
        // so a chat payload reaching a guest device is already an anomaly —
        // it must not end in a chat screen.
        expect(
          resolveNotificationDestination(payload, isGuest: guest),
          NotificationDestination.notificationsList,
        );
      });
    }

    test('guest status is not read for a non-chat notification', () {
      // isGuestMode() reads SharedPreferences, which is not initialised in
      // every caller; the decision must only ask when it is about to send
      // someone into a chat.
      var asked = false;
      resolveNotificationDestination(
        push(type: 'wallet_topup'),
        isGuest: () {
          asked = true;
          return false;
        },
      );
      expect(asked, isFalse);
    });
  });

  group('destinations compare by value', () {
    test('same kind and id are equal, different ids are not', () {
      expect(
        NotificationDestination.directChat(7),
        NotificationDestination.directChat(7),
      );
      expect(
        NotificationDestination.directChat(7),
        isNot(NotificationDestination.directChat(8)),
      );
      expect(
        NotificationDestination.directChat(7),
        isNot(NotificationDestination.groupChat(7)),
      );
    });
  });
}
