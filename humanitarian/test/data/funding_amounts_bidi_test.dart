// Campaign funding line — bidi isolation.
//
// `fundingAmountsLine` renders "raised / goal IQD". Those are two LTR numeric
// runs separated by " / ", which is bidi-neutral: inside an RTL paragraph the
// neutral takes the paragraph direction, so the runs are laid out
// right-to-left and the goal is painted where the raised amount belongs.
//
// This was live. A campaign that had raised 9,000,000 against a 500,000 goal
// displayed as "500,000 / 9,000,000" on the Arabic donate screen — which also
// made the honest "100% funded" beside it look like a contradiction, since
// 500,000 of 9,000,000 is plainly not 100%. The percentage was right; the
// amounts were being reordered by the text engine.
//
// Same defect the dashboard's formatPhone had (E1), and the same fix: wrap the
// run in U+2066 LRI … U+2069 PDI.
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_test/flutter_test.dart';

/// U+2066 LEFT-TO-RIGHT ISOLATE.
const lri = '\u2066';

/// U+2069 POP DIRECTIONAL ISOLATE.
const pdi = '\u2069';

/// Builds a campaign carrying only the fields this rule depends on.
FeaturedCampaignData campaign({required num raised, required num goal}) {
  return FeaturedCampaignData.fromJson({
    'id': 1,
    'raised_amount': raised,
    'amount_needed': goal,
    'currency': 'IQD',
  });
}

void main() {
  group('fundingAmountsLine is isolated so Arabic cannot reorder it', () {
    test('the line is wrapped in an LTR isolate', () {
      final line = campaign(raised: 9000000, goal: 500000).fundingAmountsLine;

      expect(
        line.startsWith(lri),
        isTrue,
        reason: 'missing U+2066; the numbers will swap in an RTL paragraph',
      );
      expect(line.endsWith(pdi), isTrue, reason: 'missing U+2069');
    });

    test('raised still comes before goal inside the isolate', () {
      // The reported case: 9,000,000 raised against a 500,000 goal.
      final line = campaign(raised: 9000000, goal: 500000).fundingAmountsLine;
      final inner = line.replaceAll(lri, '').replaceAll(pdi, '');

      expect(
        inner.indexOf('9,000,000') < inner.indexOf('500,000'),
        isTrue,
        reason:
            'raised must precede goal in logical order, got "$inner" — if this '
            'fails the string itself is wrong, not just its rendering',
      );
    });

    test('the percentage agrees with the amounts it sits beside', () {
      // The whole point: these two are read together on one line, so a reader
      // noticing they disagree is noticing a real defect.
      final over = campaign(raised: 9000000, goal: 500000);
      expect(over.fundedProgress, 1.0);

      final part = campaign(raised: 500000, goal: 9000000);
      expect((part.fundedProgress * 100).round(), 6);
    });

    test('an empty line stays empty rather than becoming bare isolate marks', () {
      // Both amounts absent is a real state — a campaign with no target. It
      // must return '', not a bare LRI+PDI pair, which would be an invisible
      // non-empty string and would defeat every `isNotEmpty` guard upstream.
      expect(campaign(raised: 0, goal: 0).fundingAmountsLine, '');
    });
  });
}
