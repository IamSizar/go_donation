// Pins that bad coordinates can neither blank the map nor hijack its view.
//
// THE BUG, live in production
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
// A SECOND bad row survives validation: (5, 65) is in the Indian Ocean, wrong
// but a real point on Earth. Fitting the camera to every pin therefore opened
// the map on the whole Middle East. A city guide that opens on the wrong
// continent is broken for every user, every time — so framing follows the
// city, while the outlier stays drawn on the map for whoever maintains it.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';

const LatLng _mosul = LatLng(36.3489, 43.1489);

/// A pin record in the shape the map uses.
({LatLng pos, Map<String, dynamic> entry}) _pin(double lat, double lng) =>
    (pos: LatLng(lat, lng), entry: const <String, dynamic>{});

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

    test('a far-away but POSSIBLE coordinate is still a real place', () {
      // (5, 65) survives validation on purpose — it IS a point on Earth. It is
      // handled by the framing rules below, not by pretending it is invalid.
      expect(isPlottableCoordinate(5, 65), isTrue);
    });

    test('a legitimately negative coordinate is not mistaken for invalid', () {
      expect(isPlottableCoordinate(-33.86, 151.2), isTrue); // Sydney
      expect(isPlottableCoordinate(-1.29, 36.82), isTrue); // Nairobi
    });
  });

  group('the camera frames the city, not the outliers', () {
    final mosulPins = [
      _pin(36.3489, 43.1489),
      _pin(36.3644, 43.1489),
      _pin(36.3401, 43.1326),
      _pin(36.3592, 43.1281),
      _pin(36.3750, 43.1567),
    ];

    test('a pin on another continent does not drag the opening view', () {
      final withOutlier = [...mosulPins, _pin(5, 65)];

      final framing = framingPins(withOutlier, _mosul);

      expect(
        framing.length,
        mosulPins.length,
        reason: 'the Indian Ocean pin must not decide where the map opens',
      );
      expect(framing.any((p) => p.pos.latitude == 5), isFalse);
    });

    test('every genuine Mosul place stays in frame', () {
      expect(framingPins(mosulPins, _mosul).length, mosulPins.length);
    });

    test('a neighbouring governorate still counts as near', () {
      // Erbil is ~80km from Mosul. A guide covering the region must not have
      // its neighbours cropped out of the opening view.
      final withErbil = [...mosulPins, _pin(36.19, 44.01)];
      expect(framingPins(withErbil, _mosul).length, withErbil.length);
    });

    test('when NOTHING is near the city, everything is framed', () {
      // Otherwise a directory that legitimately moves elsewhere would open on
      // an empty Mosul with every pin off screen.
      final basra = [_pin(30.5, 47.8), _pin(30.6, 47.9)];
      expect(framingPins(basra, _mosul).length, 2);
    });

    test('a single pin is returned untouched, however far away', () {
      expect(framingPins([_pin(5, 65)], _mosul).length, 1);
    });

    test('no pins at all does not throw', () {
      expect(framingPins(const [], _mosul), isEmpty);
    });
  });
}
