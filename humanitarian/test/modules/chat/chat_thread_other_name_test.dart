// Pins how the Messages list names the other party of a 1:1 thread in the
// reader's language — OPOS #26483.
//
// THE BUG
// ChatThread.fromMap filled a missing `other_name` with the English words
// "User #<id>" (blank name) or "User" (null name), and the Messages screen drew
// that field verbatim, so an Arabic user read English in the thread list.
//
// WHAT IS PINNED
//   1. The model keeps only the server's trimmed name, adding no words.
//   2. The screen fills a missing name in the reader's language, keeping the
//      user id the old fallback showed so unnamed threads stay distinguishable.
//   3. A real name is shown exactly as sent.
//   4. The Messages screen draws the resolved name, never the raw field.
//
// Expected copy is written out in full, not read from the translation map.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/models/chat_models.dart';
import 'package:flutter_application_1/modules/chat/utils/chat_sender_name.dart';

// ─── Fixtures ───

/// A thread built from the JSON the server sends. A null [name] means the
/// server sent `other_name: null`.
ChatThread _thread({String? name, int otherUserId = 57}) {
  return ChatThread.fromMap({
    'id': 3,
    'status': 'active',
    'initiated_by': 1,
    'my_role': 'donor',
    'other_user_id': otherUserId,
    'other_name': name,
  });
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  // ─── The model ───

  group('ChatThread.fromMap adds no words of its own', () {
    test('a null name keeps an empty name', () {
      expect(_thread().otherName, '');
    });

    test('a blank name keeps an empty name', () {
      expect(_thread(name: '   ').otherName, '');
    });

    test('a real name is kept, trimmed', () {
      expect(_thread(name: ' Sara Ahmed ').otherName, 'Sara Ahmed');
    });
  });

  // ─── The name the screen draws ───

  group('Arabic', () {
    setUp(() => Get.updateLocale(const Locale('ar', 'SA')));

    test('an unnamed other party reads مستخدم #id, with no English', () {
      final name = chatThreadOtherName(_thread());
      expect(name, 'مستخدم #57');
      expect(name.contains('User'), isFalse);
    });

    test('a blank name reads the same Arabic fallback', () {
      expect(chatThreadOtherName(_thread(name: ' ')), 'مستخدم #57');
    });

    test('with no usable id it reads a bare مستخدم', () {
      expect(chatThreadOtherName(_thread(otherUserId: 0)), 'مستخدم');
    });

    test('a real name is shown exactly as sent', () {
      expect(chatThreadOtherName(_thread(name: 'أحمد علي')), 'أحمد علي');
    });
  });

  group('English', () {
    setUp(() => Get.updateLocale(const Locale('en', 'US')));

    test('an unnamed other party still reads "User #id"', () {
      expect(chatThreadOtherName(_thread()), 'User #57');
    });

    test('with no usable id it reads "User"', () {
      expect(chatThreadOtherName(_thread(otherUserId: 0)), 'User');
    });
  });

  // ─── The screen ───
  //
  // A source test for the same reason as chat_sender_name_test.dart: the
  // Messages screen's controller calls ModuleApi directly with no seam.
  group('the Messages screen', () {
    const screenPath = 'lib/modules/chat/screens/messages_screen.dart';

    test('draws chatThreadOtherName, never the raw otherName field', () {
      final source = File(screenPath).readAsStringSync();
      expect(source.contains('chatThreadOtherName(thread)'), isTrue);
      expect(source.contains('thread.otherName'), isFalse);
    });
  });
}
