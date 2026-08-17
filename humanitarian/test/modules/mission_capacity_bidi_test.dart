// Mission capacity line — bidi isolation.
//
// `missionCapacityLabel` renders "@accepted / @needed volunteers". Those are
// two numeric runs separated by " / ", which is bidi-neutral: inside an RTL
// paragraph the neutral takes the paragraph direction, the runs lay out
// right-to-left, and a mission needing 8 volunteers with 1 accepted paints as
// «8 / 1» — reading as oversubscribed when it is nearly empty. It INVERTS
// recruitment status, which is the one thing this label exists to convey.
//
// Same defect as the campaign funding line (funding_amounts_bidi_test) and the
// dashboard's phone numbers (E1), and the same fix — U+2066 LRI … U+2069 PDI.
//
// WHY THIS FILE EXISTS SEPARATELY
// The funding line got a test when it was fixed; this one did not, so the
// isolate here was load-bearing and unguarded. Found while checking the live
// volunteer screen against the real mission — needed 8, accepted 1.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';

/// U+2066 LEFT-TO-RIGHT ISOLATE.
const lri = '⁦';

/// U+2069 POP DIRECTIONAL ISOLATE.
const pdi = '⁩';

Map<String, dynamic> mission({
  required int needed,
  required int accepted,
  int pending = 0,
}) => {
  'needed_volunteers': needed,
  'accepted_volunteers': accepted,
  'pending_volunteers': pending,
};

void main() {
  // Arabic specifically: the isolate exists because of what an RTL paragraph
  // does to the neutral separator, so testing this in English would pass while
  // proving nothing.
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
    Get.updateLocale(const Locale('ar', 'SA'));
  });
  tearDown(Get.reset);

  group('the accepted/needed pair is isolated', () {
    test('the real mission that exposed it: 1 accepted of 8 needed', () {
      final line = missionCapacityLabel(mission(needed: 8, accepted: 1));

      final open = line.indexOf(lri);
      final close = line.indexOf(pdi);
      expect(open, isNonNegative, reason: 'missing U+2066');
      expect(close, isNonNegative, reason: 'missing U+2069');

      // The whole point: the isolate must SPAN the slash, not sit inside one
      // number. An isolate around each number separately leaves the neutral
      // between them free to take the paragraph direction, which is the bug.
      final span = line.substring(open, close);
      expect(
        span.contains('/'),
        isTrue,
        reason:
            'the separator is outside the isolate, so the two numbers can '
            'still be reordered around it',
      );
      expect(
        span.indexOf('1'),
        lessThan(span.indexOf('8')),
        reason: 'accepted must precede needed inside the isolate',
      );
    });

    test('the pending variant is isolated too', () {
      final line = missionCapacityLabel(
        mission(needed: 8, accepted: 1, pending: 1),
      );
      final span = line.substring(line.indexOf(lri), line.indexOf(pdi));
      expect(span.contains('/'), isTrue);
      expect(span.indexOf('1'), lessThan(span.indexOf('8')));
    });

    test('a mission needing nobody says nothing about capacity', () {
      expect(missionCapacityLabel(mission(needed: 0, accepted: 0)), '');
    });

    test('pending with no target still reports the pending count', () {
      final line = missionCapacityLabel(
        mission(needed: 0, accepted: 0, pending: 3),
      );
      expect(line, isNotEmpty);
      expect(line.contains('3'), isTrue);
    });
  });
}
