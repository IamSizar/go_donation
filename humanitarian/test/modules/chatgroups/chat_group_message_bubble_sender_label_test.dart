// Pins that ChatGroupMessageBubble names the sender in the reader's language —
// OPOS #26419.
//
// WHY
// The iPhone walkthrough found "Support" and "Donor 1" in English above
// messages in an Arabic chat: the bubble drew the server's English label
// verbatim. The mapping itself is pinned word by word in
// chat_group_sender_label_test.dart; this file pins that the bubble actually
// uses it, and that a label the server did not generate (a team member's real
// name) still reaches the screen untouched.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chatgroups/models/chat_group_models.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/chat_group_message_bubble.dart';

/// Pumps two messages from other members — one per label in [labels] — in
/// [locale].
Future<void> _pumpBubbles(
  WidgetTester tester, {
  required Locale locale,
  required List<String> labels,
}) async {
  Get.locale = locale;
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      translations: AppTranslations(),
      locale: locale,
      home: Scaffold(
        body: Column(
          children: [
            for (var i = 0; i < labels.length; i++)
              ChatGroupMessageBubble(
                message: ChatGroupMessage(
                  id: i + 1,
                  senderMemberId: i + 10,
                  senderLabel: labels[i],
                  isMine: false,
                  body: 'message ${i + 1}',
                  createdAt: null,
                ),
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(Get.reset);

  testWidgets('an Arabic member reads فريق الدعم and مانح 1, not English', (
    tester,
  ) async {
    await _pumpBubbles(
      tester,
      locale: const Locale('ar', 'SA'),
      labels: const ['Support', 'Donor 1'],
    );

    expect(find.text('فريق الدعم'), findsOneWidget);
    expect(find.text('مانح 1'), findsOneWidget);
    expect(find.text('Support'), findsNothing);
    expect(find.text('Donor 1'), findsNothing);
  });

  testWidgets('an English member reads the server\'s own Support and Donor 1', (
    tester,
  ) async {
    await _pumpBubbles(
      tester,
      locale: const Locale('en', 'US'),
      labels: const ['Support', 'Donor 1'],
    );

    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Donor 1'), findsOneWidget);
  });

  testWidgets('a team member\'s real name is drawn exactly as sent', (
    tester,
  ) async {
    await _pumpBubbles(
      tester,
      locale: const Locale('ar', 'SA'),
      labels: const ['Sara Ahmed', 'Beneficiary 2'],
    );

    expect(find.text('Sara Ahmed'), findsOneWidget);
    expect(find.text('مستحق 2'), findsOneWidget);
  });
}
