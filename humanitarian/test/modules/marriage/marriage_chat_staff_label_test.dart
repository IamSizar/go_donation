// Pins the label above a staff message in the marriage chat — OPOS #26483.
//
// THE BUG
// The bubble labelled staff messages with the bare 'Support' key, whose Arabic
// is الدعم: the app's word for Kafala. TERMINOLOGY.md T10 settles that the
// support team is فريق الدعم, the words chat_group_sender_support carries and
// the 1:1 chat already uses (chatSenderName, OPOS #26435).
//
// WHY A SOURCE TEST PLUS A KEY TEST
// _Bubble is private to the conversation screen, whose State calls ModuleApi
// directly with no seam for a fake. So the source is checked for the key it
// draws, and the key is checked for the words it gives in each language.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';

const _screenPath =
    'lib/modules/marriage/screens/marriage_chat_conversation_screen.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  test('the staff label uses the support-team key, not the bare Support', () {
    final source = File(_screenPath).readAsStringSync();
    expect(source.contains("'chat_group_sender_support'.tr"), isTrue);
    expect(source.contains("'Support'.tr"), isFalse);
  });

  test('in Arabic the staff label reads فريق الدعم', () {
    Get.updateLocale(const Locale('ar', 'SA'));
    expect('chat_group_sender_support'.tr, 'فريق الدعم');
  });

  test('in English the staff label reads "Support"', () {
    Get.updateLocale(const Locale('en', 'US'));
    expect('chat_group_sender_support'.tr, 'Support');
  });
}
