// Pins that an impossible coordinate cannot blank the map.
//
// THE BUG, and it was live in production
// The City Guide map rendered as an empty grey rectangle — no tiles, no pins.
// It was not the tile server, the network, ATS or the widget: a bare map with
// the same tile source rendered Mosul perfectly. One directory row carried
// latitude 500, longitude 700.
//
// The map centred on the AVERAGE of its pins, so that single row dragged the
// centre to 90.39N / 127.98E — past the North Pole, where no tiles exist — and
// stretched the span to 495 degrees, forcing the zoom out to 6. Every user saw
// an empty rectangle because of one typo in one row.
//
// Two things were wrong and both are fixed: the app trusted coordinates it was
// handed, and it used an average as a centre. An average is not a centre — it
// is pulled by whichever point is furthest away.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';

void main() {
  group('a coordinate the Earth does not have is rejected', () {
    test('the exact row that blanked the map in production', () {
      expect(isPlottableCoordinate(500, 700), isFalse);
    });

    test('latitude beyond the poles', () {
      expect(isPlottableCoordinate(90.1, 43), isFalse);
      expect(isPlottableCoordinate(-90.1, 43), isFalse);
    });

    test('longitude beyond the antimeridian', () {
      expect(isPlottableCoordinate(36, 180.1), isFalse);
      expect(isPlottableCoordinate(36, -180.1), isFalse);
    });

    test('NaN and infinity', () {
      expect(isPlottableCoordinate(double.nan, 43), isFalse);
      expect(isPlottableCoordinate(36, double.infinity), isFalse);
      expect(isPlottableCoordinate(double.negativeInfinity, 43), isFalse);
    });

    test('null island', () {
      // (0, 0) is in the Gulf of Guinea. In a directory of Iraqi places it is
      // a coordinate that failed to parse upstream and defaulted to zero, not
      // somewhere anyone means to pin.
      expect(isPlottableCoordinate(0, 0), isFalse);
    });
  });

  group('real places are kept', () {
    test('the places actually in the directory', () {
      expect(isPlottableCoordinate(36.3489, 43.1489), isTrue); // Mosul
      expect(isPlottableCoordinate(36.3644, 43.1489), isTrue);
      expect(isPlottableCoordinate(36.3401, 43.1326), isTrue);
    });

    test('the exact limits are valid, not off-by-one rejected', () {
      expect(isPlottableCoordinate(90, 180), isTrue);
      expect(isPlottableCoordinate(-90, -180), isTrue);
    });

    test('a far-away but POSSIBLE coordinate is kept, not silently dropped', () {
      // (5, 65) is in the Indian Ocean and is almost certainly a mistake, but
      // it is a real point on Earth. Hiding it would mean nobody ever notices
      // the row is wrong; the map now simply zooms out to include it, which
      // makes the error visible instead of invisible.
      expect(isPlottableCoordinate(5, 65), isTrue);
    });

    test('a legitimately negative coordinate is not mistaken for invalid', () {
      expect(isPlottableCoordinate(-33.86, 151.2), isTrue); // Sydney
      expect(isPlottableCoordinate(-1.29, 36.82), isTrue); // Nairobi
    });
  });
}
