// Pins that a screen keeping its gutter INSIDE its own list still aligns the
// states that REPLACE that list.
//
// THE DEFECT
// A screen whose ListView carries `padding: fromLTRB(20, 0, 20, 28)` gives
// that gutter to the content and to nothing else. The skeleton and the error
// banner therefore rendered at x=0 while the rows that replace them sat in a
// 20pt margin — measured at 0.0 and 0.0 on a 400pt viewport before the fix.
// Screens that instead wrap the whole AppAsync in a Padding never had it.
// Both spellings are reasonable, which is how the app ended up with a mix.
//
// WHY THE STATES ARE ASSERTED SEPARATELY
// They do not all need the same treatment, and the tempting uniform fix — a
// default margin on AppErrorState, or padding the whole AppAsync — is wrong
// in two directions at once:
//   * AppEmpty ALREADY carries AppSpace.lg of its own, so insetting it makes
//     it the one state at 40.
//   * The content owns the padding this whole parameter exists to mirror.
// Each of those is asserted below, so a future "simplification" that pads
// everything uniformly fails here rather than shipping.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/widgets/app_states.dart';

const double _gutter = 20;

/// Long enough to fill the width it is given, so its WIDTH measures the
/// padding. Its x position would not: AppEmpty centres its text, so a short
/// message sits mid-screen whatever the padding is.
const String _longMessage =
    'This explanation is deliberately long enough to wrap, so that the width '
    'it occupies reports how much padding was applied to it.';

/// A screen shaped like the ones that had the defect: the gutter lives on the
/// content's own ListView, not on an ancestor of AppAsync.
Widget _screen({
  required bool loading,
  String? error,
  required List<String>? data,
  Widget? skeleton,
}) {
  return GetMaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: AppAsync<List<String>>(
              loading: loading,
              error: error,
              onRetry: () {},
              data: data,
              isEmpty: (list) => list.isEmpty,
              gutter: const EdgeInsets.symmetric(horizontal: _gutter),
              skeleton: skeleton,
              empty: const AppEmpty(title: 'nothing', message: _longMessage),
              builder: (list) => ListView(
                padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 28),
                children: [for (final s in list) Text(s)],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  // A fixed viewport, so the measurements below are absolute rather than
  // relative to whatever size the test harness happens to pick.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(400, 800);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);
  });

  testWidgets('the skeleton lands on the gutter, not the screen edge', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(loading: true, data: null));
    await tester.pump();

    final left = tester.getTopLeft(find.byType(AppSkeleton)).dx;
    expect(
      left,
      _gutter,
      reason: 'the skeleton rendered at $left; content sits at $_gutter',
    );
  });

  testWidgets('the error banner lands on the gutter', (tester) async {
    await tester.pumpWidget(
      _screen(loading: false, error: 'could_not_load', data: null),
    );
    await tester.pump();

    // The BOX, not the text: the banner has 12pt of padding and a 1pt border
    // of its own, so measuring the text would pass at a wrong box position.
    final banner = find
        .ancestor(
          of: find.text('could_not_load'),
          matching: find.byType(Container),
        )
        .first;
    final left = tester.getTopLeft(banner).dx;
    expect(
      left,
      _gutter,
      reason: 'the error banner rendered at $left, not the $_gutter gutter',
    );
  });

  testWidgets('the empty state is NOT inset again — it pads itself', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(loading: false, data: const []));
    await tester.pump();

    // AppEmpty carries AppSpace.lg (20) inside its own scroll view. Adding the
    // gutter on top would leave it at 40 while every other state sits at 20.
    final width = tester.getSize(find.text(_longMessage)).width;
    expect(
      width,
      400 - (2 * _gutter),
      reason:
          'the empty state measures ${400 - width} of total padding. It owns '
          'AppSpace.lg already, so the gutter must not be applied to it too.',
    );
  });

  testWidgets('the content keeps exactly its own padding', (tester) async {
    await tester.pumpWidget(_screen(loading: false, data: const ['row']));
    await tester.pump();

    final left = tester.getTopLeft(find.text('row')).dx;
    expect(
      left,
      _gutter,
      reason:
          'the content is double-padded at $left — it already carries the '
          'gutter on its own ListView',
    );
  });

  testWidgets('a caller-supplied skeleton keeps its own padding', (
    tester,
  ) async {
    // AppSkeleton.bubbles pads by 14 to match a chat transcript. The marriage
    // chat screen passes it AND needs the gutter for its error banner, so the
    // gutter must not reach a skeleton the caller chose.
    await tester.pumpWidget(
      _screen(loading: true, data: null, skeleton: AppSkeleton.bubbles()),
    );
    await tester.pump();

    final left = tester.getTopLeft(find.byType(AppSkeleton)).dx;
    expect(
      left,
      0,
      reason:
          'a passed skeleton owns its own padding; the gutter added $left on '
          'top of the 14 it already applies internally',
    );
  });
}
