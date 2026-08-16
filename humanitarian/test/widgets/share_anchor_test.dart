// Pins the anchor rect the iOS share sheet refuses to open without.
//
// WHY THIS FILE EXISTS
// "مشاركة التطبيق" (Settings ▸ Share the app) did nothing at all. No sheet, no
// error, no snackbar — the row absorbed the tap and the screen stayed put.
// Walking the surface on an iPhone 17 Pro simulator and reading the device log
// showed why:
//
//   Unhandled Exception: PlatformException(error, sharePositionOrigin:
//   argument must be set, {{0, 0}, {0, 0}} must be non-zero and within
//   coordinate space of source view: {{0, 0}, {402, 874}}, null, null)
//   #3  shareApp (package:flutter_application_1/core/app_share.dart:17:3)
//
// iOS presents the share sheet as a popover anchored to a rect in the source
// view. share_plus only sends `originX/Y/Width/Height` when the caller passes
// `sharePositionOrigin`; omit it and the iOS side reads {{0,0},{0,0}}, rejects
// it, and throws. The throw is unawaited at the tap site, so it never reached
// the user as anything — it just looked like a dead control.
//
// The same omission sat on the news-post share button, so a post share threw
// before it could record its share count.
//
// These tests assert the CHANNEL ARGUMENTS rather than the visible result: the
// share sheet is OS chrome that no widget test can see, and the argument is
// precisely what iOS rejected.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/app_share.dart';

/// The channel share_plus talks to. Mirrored from
/// share_plus_platform_interface/method_channel/method_channel_share.dart.
const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, (call) async {
          calls.add(call);
          // What the real plugin returns when the user dismisses the sheet.
          return 'dev.fluttercommunity.plus/share/unavailable';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, null);
  });

  /// The four keys share_plus derives from `sharePositionOrigin`. All absent
  /// when it is null — which is the bug.
  void expectUsableAnchor(MethodCall call) {
    final args = Map<String, dynamic>.from(call.arguments as Map);
    expect(
      args.keys,
      containsAll(<String>['originX', 'originY', 'originWidth', 'originHeight']),
      reason:
          'share_plus omits every origin key when sharePositionOrigin is null. '
          'iOS then reads {{0,0},{0,0}} and throws "sharePositionOrigin: '
          'argument must be set", so the sheet never opens.',
    );
    expect(
      (args['originWidth'] as num) > 0 && (args['originHeight'] as num) > 0,
      isTrue,
      reason:
          'iOS rejects a zero-sized anchor explicitly: the rect "must be '
          'non-zero and within coordinate space of source view". A present but '
          'empty rect fails exactly as a missing one does.',
    );
  }

  group('shareApp anchors the sheet', () {
    testWidgets('it sends a non-zero origin when given a laid-out context', (
      tester,
    ) async {
      late BuildContext tileContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 44,
                child: Builder(
                  builder: (context) {
                    tileContext = context;
                    return const Text('Share the app');
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await shareApp(tileContext);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'share');
      expectUsableAnchor(calls.single);
    });

    testWidgets('the anchor covers the widget the user actually tapped', (
      tester,
    ) async {
      late BuildContext tileContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 44,
                child: Builder(
                  builder: (context) {
                    tileContext = context;
                    return const Text('Share the app');
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await shareApp(tileContext);

      final args = Map<String, dynamic>.from(calls.single.arguments as Map);
      // On iPad the popover draws an arrow pointing at this rect, so it has to
      // be the row's own box rather than a placeholder somewhere else.
      expect(args['originWidth'], 200.0);
      expect(args['originHeight'], 44.0);
    });

    testWidgets('it still sends a usable anchor with no context at all', (
      tester,
    ) async {
      // The fallback path. `onTap: shareApp` (no context) was the shape of the
      // original call site, so the helper must not depend on getting one.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      await shareApp();

      expect(calls, hasLength(1));
      expectUsableAnchor(calls.single);
    });

    testWidgets('a context disposed mid-flight falls back instead of throwing', (
      tester,
    ) async {
      // The realistic unmounted case: the caller captured a context, awaited
      // something, and the screen went away before the share fired. The news
      // card awaits requireSignIn before acting, so this shape exists here.
      // findRenderObject() ASSERTS on a dead element rather than returning
      // null, so the helper has to check `mounted` before asking.
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox(width: 200, height: 44);
            },
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      expect(captured.mounted, isFalse, reason: 'fixture must be dead');

      await shareApp(captured);

      expect(calls, hasLength(1));
      expectUsableAnchor(calls.single);
    });
  });

  group('shareAnchor', () {
    testWidgets('a laid-out box becomes its own global rect', (tester) async {
      late BuildContext inner;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              height: 60,
              child: Builder(
                builder: (context) {
                  inner = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );

      expect(shareAnchor(inner), const Rect.fromLTWH(0, 0, 120, 60));
    });

    testWidgets('the fallback rect is non-empty and inside the window', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final rect = shareAnchor(null);

      expect(rect.isEmpty, isFalse);
      final view = tester.view;
      final size = view.physicalSize / view.devicePixelRatio;
      // "within coordinate space of source view" is the other half of what iOS
      // checks, so an off-screen fallback would fail just as loudly.
      expect(rect.left >= 0 && rect.right <= size.width, isTrue);
      expect(rect.top >= 0 && rect.bottom <= size.height, isTrue);
    });
  });
}
