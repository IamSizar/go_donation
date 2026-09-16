// Pins the one decision every Accept / Decline site now shares: which
// sentence a refused chat-invite answer shows (OPOS #26433).
//
// The server names two refusals with a `code` (`chat_lifecycle_closed`,
// `chat_invite_declined`), answers an archived thread's accept with 404, and
// refuses a decline on an active chat with an UNCODED 409 — the only 409 either
// decline route returns (chat.Store.DeclineThread and
// marriagechat.Store.DeclineThread both map "not pending" to it). Anything else
// gets a generic line with the app's recovery clause, never the exception text.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/utils/chat_invite_refusal.dart';

ApiCodedException _refusal(
  int status, {
  String code = '',
  Map<String, Object?> payload = const {},
}) => ApiCodedException(
  code: code,
  developerMessage: 'English server sentence',
  statusCode: status,
  payload: payload,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.clearTranslations();
    Get.addTranslations(AppTranslations().keys);
  });

  group('in English', () {
    setUp(() => Get.locale = const Locale('en', 'US'));

    test('a closed accept names our team and carries the reason', () {
      final text = chatInviteRefusalMessage(
        _refusal(
          409,
          code: 'chat_lifecycle_closed',
          payload: {'lifecycle': 'ended', 'lifecycle_reason': 'Duplicate'},
        ),
        ChatInviteAnswer.accept,
      );
      expect(text, contains('This conversation has been closed by our team.'));
      expect(text, contains('Duplicate'));
    });

    test('a paused accept says paused', () {
      final text = chatInviteRefusalMessage(
        _refusal(
          409,
          code: 'chat_lifecycle_closed',
          payload: {'lifecycle': 'paused'},
        ),
        ChatInviteAnswer.accept,
      );
      expect(text, 'This conversation has been paused by our team.');
    });

    test('an archived accept (404) reads as closed', () {
      expect(
        classifyChatInviteRefusal(_refusal(404), ChatInviteAnswer.accept),
        ChatInviteRefusal.closed,
      );
    });

    test('a declined invite says the user declined it', () {
      expect(
        chatInviteRefusalMessage(
          _refusal(409, code: 'chat_invite_declined'),
          ChatInviteAnswer.accept,
        ),
        'You declined this invitation.',
      );
    });

    test('an uncoded 409 on decline means already active', () {
      expect(
        classifyChatInviteRefusal(_refusal(409), ChatInviteAnswer.decline),
        ChatInviteRefusal.alreadyActive,
      );
    });

    test('anything else is a generic line, never the exception text', () {
      final accept = chatInviteRefusalMessage(
        _refusal(500),
        ChatInviteAnswer.accept,
      );
      final decline = chatInviteRefusalMessage(
        Exception('boom'),
        ChatInviteAnswer.decline,
      );
      expect(accept, startsWith('Could not accept this chat request.'));
      expect(decline, startsWith('Could not decline this chat request.'));
      expect('$accept $decline', isNot(contains('English server sentence')));
      expect(decline, isNot(contains('boom')));
    });

    test('offline advice only for a transport failure', () {
      expect(
        chatInviteRefusalMessage(
          const SocketException('down'),
          ChatInviteAnswer.accept,
        ),
        contains('Check your connection'),
      );
    });
  });

  group('in Arabic', () {
    setUp(() => Get.locale = const Locale('ar', 'SA'));

    test('each refusal reads in Arabic', () {
      expect(
        chatInviteRefusalMessage(
          _refusal(409, code: 'chat_lifecycle_closed'),
          ChatInviteAnswer.accept,
        ),
        'تم إغلاق هذه المحادثة من قِبل فريقنا.',
      );
      expect(
        chatInviteRefusalMessage(
          _refusal(409, code: 'chat_invite_declined'),
          ChatInviteAnswer.accept,
        ),
        'لقد رفضتَ هذه الدعوة.',
      );
      expect(
        chatInviteRefusalMessage(_refusal(409), ChatInviteAnswer.decline),
        'هذه المحادثة نشطة بالفعل، لذا لم يعد بالإمكان رفضها.',
      );
      expect(
        chatInviteRefusalMessage(_refusal(500), ChatInviteAnswer.accept),
        startsWith('تعذّر قبول طلب المحادثة.'),
      );
    });
  });
}
