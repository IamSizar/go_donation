// The back button on the assistant screen: close the keyboard, THEN leave.
//
// WHAT WAS REPORTED
// Pressing back on «مساعد الدعم» brought the KEYBOARD UP instead of leaving
// the screen.
//
// WHY THAT HAPPENS, AND WHY THE SCREEN NEVER SAW THE PRESS
// Android's back closes the IME itself and Flutter is never told, so the
// press that "did nothing" actually left the field FOCUSED with its input
// connection still open and no keyboard on screen. That is a state the user
// cannot see and the app has no reason to be in: the next thing that touches
// the field re-shows the keyboard, so the following back reads as summoning
// it. Releasing focus is what closes the connection, and nothing on this
// screen was doing that.
//
// WHY THIS IS A SOURCE TEST, WHICH IS WEAKER AND SAID SO PLAINLY
// It was first written as a widget test that pushed the real screen, tapped
// the field and called `handlePopRoute`. That test HANGS. BotChatScreen puts
// a live AssistantController on the network in initState, and its typing
// bubble runs a REPEATING animation, so `pumpAndSettle` never returns and
// even bounded pumps left the screen unbuilt behind a thrown error. A test
// that hangs in CI is worse than no test, so it was not kept.
//
// What is asserted here is therefore the WIRING, not the behaviour: that the
// screen owns the focus node, that back is intercepted rather than left to
// pop, and that the intercept releases focus. The behaviour itself — one
// press closes the keyboard, the next leaves the screen — was verified by
// hand on a Motorola Defy, and that verification is what this file is a
// cheap regression guard for, not a replacement for.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screen = 'lib/modules/bot/screens/bot_chat_screen.dart';

String _source() {
  final file = File(_screen);
  if (!file.existsSync()) {
    fail('$_screen is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

void main() {
  group('the assistant sequences the back button', () {
    test('back is intercepted rather than left to pop', () {
      final source = _source();
      expect(
        source.contains('canPop: false'),
        isTrue,
        reason:
            'without an interception the framework pops first and the focus '
            'question is never asked — which is the reported bug',
      );
      expect(
        source.contains('onPopInvokedWithResult: _handlePop'),
        isTrue,
        reason: 'the intercept has to be wired to the handler that decides',
      );
    });

    test('the handler releases focus before it considers leaving', () {
      final source = _source();
      final handler = source.substring(
        source.indexOf('void _handlePop('),
        source.indexOf('// Note #40'),
      );
      expect(
        handler.contains('_inputFocus.hasFocus') &&
            handler.contains('_inputFocus.unfocus()'),
        isTrue,
        reason:
            'releasing focus is what closes the input connection; without it '
            'the keyboard comes back on the next press',
      );
      // pop(), not maybePop(): maybePop consults this screen's own PopScope
      // (canPop: false) and lands straight back in this handler, so the
      // screen can never be left. Observed on the device.
      // Matched on the CALL, not the word: the comment above it explains why
      // maybePop is wrong, and naming it there must not fail this.
      expect(
        handler.contains('Navigator.of(context).pop()') &&
            !handler.contains('.maybePop()'),
        isTrue,
        reason:
            'and with no keyboard up the press must still leave — swallowing '
            'every press traps the user on the assistant, which is worse than '
            'the bug being fixed',
      );
    });

    test('focus is released when the keyboard closes, not when back arrives', () {
      final source = _source();
      expect(
        source.contains('void didChangeMetrics()') &&
            source.contains('View.of(context).viewInsets.bottom'),
        isTrue,
        reason:
            'the press that closes the keyboard never reaches the app, so the '
            'inset is the only signal there is. Without it the field stays '
            'focused with no keyboard — and releasing focus in _handlePop '
            'instead just moves the cost to the next press: MEASURED on a '
            'Motorola, that made leaving the screen take three presses.',
      );
      // The first version of this shipped an ANR: unfocusing changes the
      // metrics, which scheduled another check, which unfocused again. Both
      // guards are what stop it feeding itself, so both are pinned.
      expect(
        source.contains('_keyboardWasOpen') &&
            source.contains('_metricsCheckQueued'),
        isTrue,
        reason:
            'without the open→closed transition and the single-pending-check '
            'guard, this handler re-triggers itself and Android puts up '
            '"BalanceNex isn\'t responding" — observed on the device',
      );
    });

    test('dragging the conversation puts the keyboard away (rule 5.6)', () {
      expect(
        _source().contains('ScrollViewKeyboardDismissBehavior.onDrag'),
        isTrue,
        reason:
            'reading the answer is the commonest reason to touch this list '
            'while typing, and the keyboard covers half of it',
      );
    });
  });
}
