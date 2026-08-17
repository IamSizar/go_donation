// Guards against a raw Dart exception being rendered to a user.
//
// THE SHAPE OF THE BUG
// A catch block assigns the exception straight to something the UI draws:
//
//     errorMessage.value = e.toString();
//     SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))
//     errorMessage.value = 'An error occurred: @error'.trParams({'error': e.toString()})
//
// which renders "Exception: Request failed (401)" on screen. Three faults at
// once: a status code the reader cannot act on, English text on an Arabic
// screen, and the impression that the app broke rather than a request failing.
// The last form is the worst, because the sentence around it IS localized, so
// the line looks handled.
//
// Found on the beneficiary's سجلي screen, whose error card read
// "حدث خطأ ما / Exception: Request failed (401)". The same file already
// resolved a message key two branches below, so the convention existed and one
// branch had simply missed it.
//
// THE RULE
// `e.toString()` may go to a log — debugPrint, log(), a diagnostic map — and
// must not reach a widget or an observable the UI binds to. `failureMessage`
// exists for that: it names what failed, adds what to do next, and tells
// offline apart from a server refusal.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sinks that end up on screen. Deliberately narrow: matching every use of
/// toString() would drown in false positives from logging, which is the one
/// place the raw text belongs.
final _uiSinks = <RegExp>[
  // errorMessage.value = e.toString() / .message = err.toString()
  RegExp(r'(errorMessage|errorText|message)\s*\.\s*value\s*=\s*[^;]*\b\w*\.toString\(\)'),
  // Text(e.toString()) — including a .replaceFirst('Exception: ') dressing,
  // which removes the word "Exception" and keeps the status code.
  RegExp(r'Text\(\s*\w+\.toString\(\)'),
  // A localized template with the exception interpolated into it.
  RegExp(r"trParams\(\{[^}]*'error'\s*:\s*\w+\.toString\(\)", dotAll: true),
];

/// Lines that are allowed to carry the raw text — the log is exactly where it
/// should go, so a diagnostic sink is not a leak.
bool _isLogSink(String line) {
  final l = line.trimLeft();
  return l.startsWith('//') ||
      l.startsWith('*') ||
      line.contains('debugPrint(') ||
      line.contains('log(') ||
      line.contains('print(');
}

void main() {
  test('no raw exception text is bound to anything the UI renders', () {
    final leaks = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (_isLogSink(line)) continue;
        for (final sink in _uiSinks) {
          if (sink.hasMatch(line)) {
            leaks.add('${entity.path}:${i + 1}  ${line.trim()}');
            break;
          }
        }
      }
    }

    expect(
      leaks,
      isEmpty,
      reason:
          'These put a raw exception where a user can read it. Send the detail '
          'to a log and give the screen copy — failureMessage(e, '
          "'error_<what>_failed') — so the reader gets a sentence in their own "
          'language instead of a status code:\n  ${leaks.join('\n  ')}',
    );
  });
}
