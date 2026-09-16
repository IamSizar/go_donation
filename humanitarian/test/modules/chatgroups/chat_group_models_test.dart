import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/modules/chatgroups/models/chat_group_models.dart';

void main() {
  group('ChatGroupSummary', () {
    test('parses a masked group with no title', () {
      final g = ChatGroupSummary.fromMap({
        'id': 7,
        'kind': 'masked',
        'title': '',
        'unread_count': 2,
        'last_message': 'Hello',
        'last_at': '2026-09-14T10:00:00Z',
      });
      expect(g.id, 7);
      expect(g.kind, 'masked');
      expect(g.isMasked, true);
      expect(g.title, '');
      expect(g.unreadCount, 2);
      expect(g.lastMessage, 'Hello');
      expect(g.lastAt, isNotNull);
    });

    test('parses a team group with a title', () {
      final g = ChatGroupSummary.fromMap({
        'id': 9,
        'kind': 'team',
        'title': 'Distribution team',
        'unread_count': 0,
        'last_message': '',
        'last_at': '2026-09-14T10:00:00Z',
      });
      expect(g.isMasked, false);
      expect(g.title, 'Distribution team');
    });
  });

  group('ChatGroupMessage', () {
    test('parses a message with no user-id field to leak', () {
      final m = ChatGroupMessage.fromMap({
        'id': 1,
        'sender_member_id': 3,
        'sender_label': 'Donor 1',
        'is_mine': false,
        'body': 'Hi there',
        'created_at': '2026-09-14T10:00:00Z',
      });
      expect(m.senderLabel, 'Donor 1');
      expect(m.isMine, false);
      expect(m.body, 'Hi there');
    });
  });

  group('MyConnectRequest', () {
    test('parses a pending request with no group yet', () {
      final r = MyConnectRequest.fromMap({
        'id': 5,
        'context_type': 'donation',
        'context_id': 42,
        'message': 'Please connect me',
        'status': 'pending',
        'created_at': '2026-09-14T10:00:00Z',
      });
      expect(r.status, 'pending');
      expect(r.groupId, isNull);
      expect(r.declineReason, isNull);
    });

    test('parses a declined request with a reason', () {
      final r = MyConnectRequest.fromMap({
        'id': 6,
        'context_type': 'case',
        'context_id': 3,
        'message': 'Help please',
        'status': 'declined',
        'decline_reason': 'Not eligible for this campaign.',
        'created_at': '2026-09-14T10:00:00Z',
      });
      expect(r.status, 'declined');
      expect(r.declineReason, 'Not eligible for this campaign.');
    });
  });
}
