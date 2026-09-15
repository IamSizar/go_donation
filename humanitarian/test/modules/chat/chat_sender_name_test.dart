// Pins how the 1:1 chat names a message's sender in the reader's language —
// OPOS #26435.
//
// THE BUG
// ChatMessage.fromMap filled a missing sender name with the English words
// "Support" (a staff reply) or "User" (anyone else), and the conversation
// screen drew that field verbatim, so an Arabic user read "Support" in English
// above a support reply. The name really does go missing in production: the
// server sends the sender's profile full_name, which is null when the staff
// account has no profile name or when the viewer's privacy rules hide it.
// backend/internal/privacy Viewer.Name returns nil on purpose and leaves the
// placeholder to the client.
//
// WHAT IS PINNED
//   1. The model keeps what the server sent and adds no words of its own, so it
//      stays independent of the reader's language.
//   2. The screen fills a missing name in the reader's language. The support
//      team is فريق الدعم in Arabic and "Support" in English: the same words the
//      chat groups sign staff messages with (chat_group_sender_support), never a
//      bare الدعم, which is Kafala (TERMINOLOGY.md T10).
//   3. A real name, a staff member's or anyone else's, is shown exactly as sent.
//   4. The conversation screen actually draws the resolved name.
//
// The expected copy is written out in full rather than read from the
// translation map: a test that looked the value up would pass whatever the
// value said.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/models/chat_models.dart';
import 'package:flutter_application_1/modules/chat/utils/chat_sender_name.dart';

// ─── Fixtures ───

/// `sender_role` for a staff reply (ChatMessage.isSupport).
const _supportRole = 0;

/// `sender_role` for a donor, one of the non-staff roles.
const _donorRole = 1;

/// A message built from the JSON the server sends. A null [name] means the
/// server sent `sender_name: null`, as it does for a hidden or missing name.
ChatMessage _message({required int role, String? name}) {
  return ChatMessage.fromMap({
    'id': 1,
    'thread_id': 7,
    'sender_user_id': 42,
    'sender_role': role,
    'sender_name': name,
    'body': 'hello',
    'created_at': '2026-09-15T12:00:00Z',
  });
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  // ─── The model ───

  group('ChatMessage.fromMap adds no words of its own', () {
    test('a support reply with no name keeps an empty name', () {
      expect(_message(role: _supportRole).senderName, '');
    });

    test('any other sender with no name keeps an empty name', () {
      expect(_message(role: _donorRole).senderName, '');
    });

    test('a blank name counts as no name', () {
      expect(_message(role: _supportRole, name: '   ').senderName, '');
    });

    test('a real name is kept, trimmed', () {
      expect(
        _message(role: _supportRole, name: ' Sara Ahmed ').senderName,
        'Sara Ahmed',
      );
    });
  });

  // ─── The name the screen draws ───

  group('Arabic', () {
    setUp(() => Get.updateLocale(const Locale('ar', 'SA')));

    test('an unnamed support reply reads فريق الدعم', () {
      expect(chatSenderName(_message(role: _supportRole)), 'فريق الدعم');
    });

    test('an unnamed sender who is not staff reads مستخدم', () {
      expect(chatSenderName(_message(role: _donorRole)), 'مستخدم');
    });

    test("a staff member's real name is shown exactly as sent", () {
      expect(
        chatSenderName(_message(role: _supportRole, name: 'سارة أحمد')),
        'سارة أحمد',
      );
      // A Latin-script name is still a name, not English UI copy.
      expect(
        chatSenderName(_message(role: _supportRole, name: 'Sara Ahmed')),
        'Sara Ahmed',
      );
    });

    test("another sender's real name is shown exactly as sent", () {
      expect(
        chatSenderName(_message(role: _donorRole, name: 'أحمد علي')),
        'أحمد علي',
      );
    });
  });

  group('English', () {
    setUp(() => Get.updateLocale(const Locale('en', 'US')));

    test('an unnamed support reply reads "Support"', () {
      expect(chatSenderName(_message(role: _supportRole)), 'Support');
    });

    test('an unnamed sender who is not staff reads "User"', () {
      expect(chatSenderName(_message(role: _donorRole)), 'User');
    });

    test("a staff member's real name is shown exactly as sent", () {
      expect(
        chatSenderName(_message(role: _supportRole, name: 'Sara Ahmed')),
        'Sara Ahmed',
      );
    });
  });

  group('Kurdish', () {
    test('an unnamed support reply never falls back to Arabic', () {
      // Kurdish is written in Arabic script, so an Arabic label would look
      // plausible and still be the wrong language. With no Kurdish entry the
      // required fallback is English.
      for (final locale in const [Locale('ar', 'IQ'), Locale('ar', 'TR')]) {
        Get.locale = locale;
        final name = chatSenderName(_message(role: _supportRole));
        expect(name, isNotEmpty, reason: 'nothing drawn in $locale');
        expect(name, isNot('فريق الدعم'), reason: 'Arabic leaked in $locale');
      }
    });
  });

  // ─── The screen ───
  //
  // WHY A SOURCE TEST
  // ChatConversationScreen puts a ChatThreadController in initState, and that
  // controller calls `const ModuleApi()` directly on init and every 3 seconds,
  // with no seam to hand it a fake. The same reason keeps
  // messages_support_doors_test.dart from pumping MessagesScreen. What matters
  // here is a property of the source: the bubble draws the resolved name, not
  // the raw field.
  group('the conversation screen', () {
    const screenPath = 'lib/modules/chat/screens/chat_conversation_screen.dart';

    String readScreen() {
      final file = File(screenPath);
      if (!file.existsSync()) {
        fail('$screenPath is missing — this test needs updating');
      }
      return file.readAsStringSync();
    }

    test('draws chatSenderName, never the raw senderName field', () {
      final source = readScreen();

      expect(
        source.contains('chatSenderName(message)'),
        isTrue,
        reason: 'the sender label must go through chatSenderName',
      );
      expect(
        RegExp(r'Text\(\s*message\.senderName').hasMatch(source),
        isFalse,
        reason:
            'the raw field has no fallback, so an unnamed sender would '
            'draw an empty label',
      );
    });
  });
}
