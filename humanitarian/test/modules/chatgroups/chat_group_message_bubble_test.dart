// Pins ChatGroupMessageBubble's text direction — OPOS #25284 Phase 5.
//
// WHAT IS PINNED
//   A message body is laid out in the direction of what was typed, not the
//   direction of the app. The iPhone walkthrough found an English message on
//   an Arabic screen drawn as ".campaign": the paragraph took the screen's
//   right-to-left direction, which moved its full stop to the wrong end. An
//   Arabic message on an English screen has the mirror-image problem.
//   Content with no letters at all keeps following the screen.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chatgroups/models/chat_group_models.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/chat_group_message_bubble.dart';

/// Pumps one bubble holding [body] on a screen laid out in [screenDirection].
Future<void> _pumpBubble(
  WidgetTester tester, {
  required String body,
  required TextDirection screenDirection,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      home: Directionality(
        textDirection: screenDirection,
        child: Scaffold(
          body: ChatGroupMessageBubble(
            message: ChatGroupMessage(
              id: 1,
              senderMemberId: 3,
              senderLabel: 'Donor 1',
              isMine: false,
              body: body,
              createdAt: null,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The direction the body is actually laid out in on screen — read from the
/// paragraph, so it holds however the bubble chooses to set it.
TextDirection _laidOutDirection(WidgetTester tester, String body) =>
    tester.renderObject<RenderParagraph>(find.text(body)).textDirection;

void main() {
  testWidgets('an English message on an Arabic screen reads left-to-right', (
    tester,
  ) async {
    const body = 'Hello, I donated to the winter campaign.';
    await _pumpBubble(
      tester,
      body: body,
      screenDirection: TextDirection.rtl,
    );

    expect(_laidOutDirection(tester, body), TextDirection.ltr);
  });

  testWidgets('an Arabic message on an English screen reads right-to-left', (
    tester,
  ) async {
    const body = 'شكراً لكم جميعاً.';
    await _pumpBubble(
      tester,
      body: body,
      screenDirection: TextDirection.ltr,
    );

    expect(_laidOutDirection(tester, body), TextDirection.rtl);
  });

  testWidgets('a message with no letters follows the screen', (tester) async {
    const body = '33';
    await _pumpBubble(
      tester,
      body: body,
      screenDirection: TextDirection.rtl,
    );

    expect(_laidOutDirection(tester, body), TextDirection.rtl);
  });
}
