// Pins that the map's chip describes the places it is actually showing.
//
// THE BUG
// The chip read "@count places · Mosul" — with Mosul written into the
// translation key itself. It was used on every city's map, so the map asserted
// Mosul over places in every other governorate. An earlier fix had corrected
// the TRANSLATION of that string and left the hardcoded city sitting inside
// it, which is why it survived a localisation pass.
//
// Reported as part of "the map shows but it shows wrong".
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';

Map<String, dynamic> _place(String city, {double? lat, double? lng}) => {
  'city': city,
  'latitude': lat,
  'longitude': lng,
};

void main() {
  setUp(() {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
  });

  test('the chip never claims a city the places are not in', () {
    final label = cityMapChipLabel(
      pinCount: 3,
      source: [_place('Erbil'), _place('Erbil'), _place('Erbil')],
    );

    expect(
      label.contains('Mosul'),
      isFalse,
      reason: 'the map asserted Mosul over places in every other governorate',
    );
    expect(label, contains('Erbil'));
    expect(label, contains('3'));
  });

  test('places spanning several cities are given NO city', () {
    // There is no single true answer here, and picking one would be the same
    // defect in a quieter form.
    final label = cityMapChipLabel(
      pinCount: 2,
      source: [_place('Erbil'), _place('Basra')],
    );

    expect(label, contains('2'));
    expect(label.contains('·'), isFalse, reason: 'no city should be named');
  });

  test('one place reads as singular', () {
    final label = cityMapChipLabel(pinCount: 1, source: [_place('Erbil')]);
    expect(label, contains('1 place'));
    expect(label.contains('1 places'), isFalse);
  });

  test('entries with no city at all still report a count', () {
    final label = cityMapChipLabel(pinCount: 4, source: [_place('')]);
    expect(label, contains('4'));
    expect(label.contains('·'), isFalse);
  });

  test('the city is localized, not echoed raw', () {
    Get.locale = const Locale('ar', 'SA');
    final label = cityMapChipLabel(pinCount: 1, source: [_place('Erbil')]);

    expect(
      label.contains('Erbil'),
      isFalse,
      reason: 'an Arabic reader must not be shown the raw stored value',
    );
    expect(label, contains('أربيل'));
  });

  test('a changed filter counts as moved pins, so the camera follows', () {
    final erbil = [_place('Erbil', lat: 36.19, lng: 44.01)];
    final basra = [_place('Basra', lat: 30.5, lng: 47.8)];

    expect(
      cityMapPinsUnchanged(erbil, basra),
      isFalse,
      reason:
          'the camera must follow the filtered list; initialCenter is '
          'one-shot and will not move it',
    );
  });

  test('a rebuild that moves no pin does NOT move the camera', () {
    // The parent rebuilds for reasons unrelated to the pins. Re-centring on
    // those would yank the map away from a user who had just panned.
    final before = [_place('Erbil', lat: 36.19, lng: 44.01)];
    final after = [_place('Erbil', lat: 36.19, lng: 44.01)];

    expect(cityMapPinsUnchanged(before, after), isTrue);
  });

  test('a list of a different length always counts as changed', () {
    expect(
      cityMapPinsUnchanged(
        [_place('Erbil', lat: 36.19, lng: 44.01)],
        [
          _place('Erbil', lat: 36.19, lng: 44.01),
          _place('Erbil', lat: 36.20, lng: 44.02),
        ],
      ),
      isFalse,
    );
  });
}

// ─── The camera-follows-the-filter rule ─────────────────────────────────────
//
// MapOptions.initialCenter/initialZoom are one-shot: flutter_map reads them
// when the map is created and ignores them forever after. Without an explicit
// re-centre, filtering by sector or searching changed the list underneath
// while the camera stayed put, so the visible area stopped matching the places
// the screen claimed to be showing.
//
// The comparison is by COORDINATES rather than list identity because the
// parent rebuilds this widget for reasons that move no pin — re-centring on
// those would yank the map away from a user who had just panned somewhere.
