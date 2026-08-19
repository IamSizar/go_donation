// Fails when a fixed foreground colour sits on a theme-dependent background.
//
// THE BUG
// «حفظ الملف الشخصي» measured 2.19:1 in dark mode — white text on the accent.
// It is fine in light mode, because the light accent is a dark green. The dark
// accent is a LIGHT mint, so the same literal white becomes nearly invisible.
//
// The palette already had the right answer: onAccent is #FFFFFF in light and
// #10201B in dark, precisely so a filled surface's label flips with the theme.
// Nothing was missing except call sites using it.
//
// WHY A SOURCE RULE AND NOT A CONTRAST TEST
// Measuring contrast needs a rendered frame, a theme, and a screen to put it
// on, which is a lot of machinery to catch "somebody wrote Colors.white". The
// defect has a syntactic shape: a literal foreground paired with a background
// that varies by theme. That is cheap to detect and impossible to argue with.
//
// It does NOT flag a literal foreground on a FIXED background — white on the
// brand primary, on WhatsApp green, on a pinned map colour — because those do
// not change with the theme and were measured fine.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reads every .dart file under lib/.
Iterable<({String path, List<String> lines})> _libSources() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    yield (path: entity.path, lines: entity.readAsLinesSync());
  }
}

void main() {
  test('a fixed foreground never sits on a theme-dependent background', () {
    // `backgroundColor: something(context)` — the (context) is what makes it
    // theme-dependent, and therefore different in dark mode.
    final themedBackground = RegExp(r'backgroundColor:\s*[\w.]*\w+\(context\)');
    final fixedForeground = RegExp(
      r'foregroundColor:\s*(Colors\.\w+|Color\(0x[0-9a-fA-F]+\))',
    );

    final offenders = <String>[];
    for (final file in _libSources()) {
      for (var i = 0; i < file.lines.length; i++) {
        if (!themedBackground.hasMatch(file.lines[i])) continue;
        // Look a few CODE lines either way — counting raw lines instead let a
        // reintroduced defect slip past, because the explanatory comment added
        // beside the fix pushed the foreground outside the window. Found by
        // mutation-testing this guard, not by reading it.
        final nearby = <int>[];
        for (final dir in [-1, 1]) {
          var seen = 0;
          for (var j = i + dir; j >= 0 && j < file.lines.length; j += dir) {
            final t = file.lines[j].trim();
            if (t.isEmpty || t.startsWith('//')) continue; // not a code line
            nearby.add(j);
            if (++seen >= 4) break;
          }
        }
        for (final j in nearby) {
          if (!fixedForeground.hasMatch(file.lines[j])) continue;
          offenders.add(
            '${file.path}:${j + 1}  ${file.lines[j].trim()}'
            '   (background at line ${i + 1})',
          );
          break;
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A background that changes with the theme needs a foreground that '
          'changes with it too. These pair a literal colour with a themed '
          'background, so one of the two appearances is wrong:\n'
          '${offenders.join('\n')}\n\n'
          'Use AppThemeConfig.onAccent(context), which is white in light and '
          'near-black in dark. If the background is genuinely FIXED (the brand '
          'primary, a partner brand colour), write the literal background too '
          'so the pair is obviously deliberate.',
    );
  });
}
