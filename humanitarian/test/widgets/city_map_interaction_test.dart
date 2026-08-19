// Pins that the City Guide map answers a ONE-FINGER drag.
//
// THE BUG, reported as "the map on the city guide doesnt work"
// Panning had been restricted to two fingers. Nothing was broken in the usual
// senses — the tiles served 200s and 8 of the 9 directory entries carried
// coordinates — but a one-finger drag did nothing, and that is the gesture
// every person tries first. A map that ignores it reads as broken rather than
// as restricted.
//
// The restriction had a real reason once: a single-finger drag was swallowed
// by the map instead of scrolling the page behind it. The layout changed
// underneath that decision and left it protecting nothing. See the doc comment
// on [cityMapInteraction] for the ancestor chain that establishes there is no
// longer anything behind the map to scroll.
//
// The drag test below is the one that matters. The flag assertions are cheap
// extra detail about intent, but they would pass against a map that still did
// not move, so they are not the proof on their own.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';

const LatLng _mosul = LatLng(36.3489, 43.1489);

void main() {
  testWidgets('one finger pans the map', (tester) async {
    final controller = MapController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: FlutterMap(
              mapController: controller,
              // The REAL options object the screen uses, not a copy — a copy
              // would keep passing after someone changed the screen.
              options: const MapOptions(
                initialCenter: _mosul,
                initialZoom: 13,
                interactionOptions: cityMapInteraction,
              ),
              children: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final before = controller.camera.center;

    // A single pointer, dragged. This is the gesture that did nothing.
    await tester.drag(find.byType(FlutterMap), const Offset(-120, -90));
    await tester.pumpAndSettle();

    final after = controller.camera.center;

    expect(
      after == before,
      isFalse,
      reason:
          'the map did not move for a one-finger drag. That is the gesture '
          'everyone tries first, and ignoring it is what "the map does not '
          'work" meant.',
    );
  });

  test('the gesture set says what it means', () {
    final flags = cityMapInteraction.flags;

    expect(
      InteractiveFlag.hasDrag(flags),
      isTrue,
      reason: 'one-finger pan is the map\'s primary gesture',
    );
    expect(
      InteractiveFlag.hasPinchZoom(flags),
      isTrue,
      reason: 'pinch zoom worked before this fix and must keep working',
    );
    expect(
      InteractiveFlag.hasDoubleTapZoom(flags),
      isTrue,
      reason: 'double-tap zoom worked before this fix and must keep working',
    );
    expect(
      InteractiveFlag.hasRotate(flags),
      isFalse,
      reason:
          'rotation stays OFF on purpose: an accidental two-finger twist has '
          'no reset control on this screen, so it strands the user',
    );
  });
}
