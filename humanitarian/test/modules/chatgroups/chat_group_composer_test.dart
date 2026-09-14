// Pins ChatGroupComposer — the message box and send button of a chat-group
// conversation, OPOS #25284 Phase 5 Task 3.
//
// WHAT IS PINNED
//   1. Rule 5.6: the send button is disabled — and looks it — until something
//      other than whitespace is typed. A button that silently does nothing is
//      a doomed request in disguise.
//   2. While a send is in flight the button ignores taps.
//   3. The in-button spinner is visible on BOTH platforms. Review found that
//      `CircularProgressIndicator.adaptive` ignores `valueColor` on iOS and
//      draws its default grey ticks — about 1.5:1 against the accent fill, so
//      an iPhone user saw a blank green circle while sending. Adaptive widgets
//      are tested on both targets (rule 7.1).
//   4. Focusing the draft keeps its pill outline. The device walkthrough found
//      the app theme's focused border is a flat underline, so a field that set
//      only its resting outlines lost its rounded shape the moment it was
//      tapped (rule 4.5: rounded inputs with a visible focus state).
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/chat_group_composer.dart';

const _sendButton = Key('chat_group_send');

/// Pumps the composer alone, on [platform].
Future<void> _pumpComposer(
  WidgetTester tester, {
  required TextEditingController input,
  required VoidCallback onSend,
  required bool isSending,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeConfig.buildTheme(
        Brightness.light,
      ).copyWith(platform: platform),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatGroupComposer(
            input: input,
            onSend: onSend,
            isSending: isSending,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The opacity the send button is drawn at. The innermost Opacity is the
/// button's own; AppPressable adds an outer one for press feedback.
double _sendOpacity(WidgetTester tester) => tester
    .widgetList<Opacity>(
      find.descendant(
        of: find.byKey(_sendButton),
        matching: find.byType(Opacity),
      ),
    )
    .last
    .opacity;

void main() {
  testWidgets('the send button is disabled until something is typed', (
    tester,
  ) async {
    final input = TextEditingController();
    var sends = 0;
    await _pumpComposer(
      tester,
      input: input,
      onSend: () => sends++,
      isSending: false,
    );

    expect(_sendOpacity(tester), lessThan(1), reason: 'must look disabled');
    await tester.tap(find.byKey(_sendButton));
    await tester.pump();
    expect(sends, 0, reason: 'nothing typed');

    input.text = '   ';
    await tester.pump();
    await tester.tap(find.byKey(_sendButton));
    await tester.pump();
    expect(sends, 0, reason: 'only whitespace typed');

    input.text = 'Hello';
    await tester.pump();
    expect(_sendOpacity(tester), 1, reason: 'must look ready once enabled');
    await tester.tap(find.byKey(_sendButton));
    await tester.pump();
    expect(sends, 1);
  });

  testWidgets('focusing the draft keeps its rounded outline, in the accent', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      input: TextEditingController(),
      onSend: () {},
      isSending: false,
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    final decorator = tester.widget<InputDecorator>(
      find.byType(InputDecorator),
    );
    expect(decorator.isFocused, isTrue);
    final focused = decorator.decoration.focusedBorder;
    expect(
      focused,
      isA<OutlineInputBorder>(),
      reason: 'the theme default is a flat underline, which drops the pill',
    );
    final outline = focused! as OutlineInputBorder;
    expect(outline.borderRadius, BorderRadius.circular(AppRadius.full));
    expect(
      outline.borderSide.color,
      AppThemeConfig.accent(tester.element(find.byType(ChatGroupComposer))),
    );
  });

  testWidgets('while sending, the button ignores taps', (tester) async {
    var sends = 0;
    await _pumpComposer(
      tester,
      input: TextEditingController(text: 'Hello'),
      onSend: () => sends++,
      isSending: true,
    );

    await tester.tap(find.byKey(_sendButton));
    await tester.pump();

    expect(sends, 0);
  });

  testWidgets('while sending on iOS, the spinner is drawn in the foreground', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      input: TextEditingController(text: 'Hello'),
      onSend: () {},
      isSending: true,
      platform: TargetPlatform.iOS,
    );

    final foreground = AppThemeConfig.onAccent(
      tester.element(find.byType(ChatGroupComposer)),
    );
    final spinner = tester.widget<CupertinoActivityIndicator>(
      find.byType(CupertinoActivityIndicator),
    );
    expect(spinner.color, foreground);
  });

  testWidgets(
    'while sending on Android, the spinner is drawn in the foreground',
    (tester) async {
      await _pumpComposer(
        tester,
        input: TextEditingController(text: 'Hello'),
        onSend: () {},
        isSending: true,
      );

      final foreground = AppThemeConfig.onAccent(
        tester.element(find.byType(ChatGroupComposer)),
      );
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.valueColor?.value, foreground);
    },
  );
}
