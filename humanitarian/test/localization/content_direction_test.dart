// Pins that user-written content is laid out in its OWN direction.
//
// THE BUG
// A marriage/events profile bio written in English rendered inside the Arabic
// UI as ".life's journey" — the full stop moved to the far end of the line.
// Nothing was wrong with the stored string; the paragraph was simply being
// laid out right-to-left because the screen was.
//
// WHY A DIRECTION AND NOT AN ISOLATE
// An isolate character fixes a short run sitting inside a sentence. A bio IS
// the sentence, so it needs a real text direction — otherwise wrapping and
// alignment stay wrong even when the punctuation is fixed.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/localization/content_localizer.dart';

void main() {
  test('English content is laid out left-to-right even on an Arabic screen', () {
    expect(
      contentDirection("Seeking a partner to share life's journey.",
          fallback: TextDirection.rtl),
      TextDirection.ltr,
    );
  });

  test('Arabic content is laid out right-to-left even on an English screen', () {
    expect(
      contentDirection('يمتلك متجرًا صغيرًا للإلكترونيات.',
          fallback: TextDirection.ltr),
      TextDirection.rtl,
    );
  });

  test('mixed content follows the strong characters it contains', () {
    // Arabic present anywhere wins: the sentence reads as Arabic prose that
    // happens to quote a Latin word, which is the common real case here.
    expect(
      contentDirection('يعمل في Google', fallback: TextDirection.ltr),
      TextDirection.rtl,
    );
  });

  test('content with no strong direction follows the reader', () {
    for (final neutral in ['33', '   ', '', '2026 — 33']) {
      expect(contentDirection(neutral, fallback: TextDirection.rtl),
          TextDirection.rtl,
          reason: '"$neutral" has no direction of its own');
      expect(contentDirection(neutral, fallback: TextDirection.ltr),
          TextDirection.ltr,
          reason: '"$neutral" has no direction of its own');
    }
  });

  test('emoji-only content is treated as LTR, as intl classifies it', () {
    // Pinned because it contradicts the "neutral follows the reader" rule
    // above, and a future reader would otherwise assume it a bug.
    expect(contentDirection('👍', fallback: TextDirection.rtl),
        TextDirection.ltr);
  });
}
