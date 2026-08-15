// Tests for the four-state switcher and the row primitives.
//
// The audit's finding was not that these states were badly built — it was
// that they were MISSING: skeletons on 1 of 116 surfaces, retry on 9 of 58
// app screens and 0 of 58 console pages. So these tests pin the state
// transitions themselves, and one pins right-to-left mirroring, because
// three of the app's four languages are RTL and the audit found 15 hard-coded
// physical layout values.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/widgets/app_row.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

Widget _host(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      extensions: <ThemeExtension<dynamic>>[
        brightness == Brightness.dark ? AppColors.dark : AppColors.light,
      ],
    ),
    home: Directionality(
      textDirection: direction,
      child: Scaffold(body: child),
    ),
  );
}

/// Builds an AppAsync with sensible defaults so each test varies one thing.
Widget _async({
  required bool loading,
  String? error,
  List<String>? data,
  VoidCallback? onRetry,
}) {
  return _host(
    AppAsync<List<String>>(
      loading: loading,
      error: error,
      onRetry: onRetry ?? () {},
      data: data,
      isEmpty: (items) => items.isEmpty,
      empty: const AppEmpty(
        title: 'Nothing here yet',
        message: 'When you give, your gifts appear here.',
      ),
      builder: (items) => Column(children: [for (final i in items) Text(i)]),
    ),
  );
}

void main() {
  group('AppAsync renders exactly one state', () {
    testWidgets('first load shows a skeleton, not a spinner', (tester) async {
      await tester.pumpWidget(_async(loading: true, data: null));
      await tester.pump();

      expect(find.byType(AppSkeleton), findsOneWidget);
      // The point of the finding: a spinner is not an acceptable substitute.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(AppEmpty), findsNothing);
    });

    testWidgets('a first load holding an empty list still shows the skeleton', (
      tester,
    ) async {
      // Pins a flaw found while wiring the marriage screens. Most screens here
      // declare their list as `const []` rather than null, so during the first
      // load AppAsync saw a non-null-but-empty value and rendered the EMPTY
      // state — telling the user there was nothing before the request had even
      // answered. Empty is a claim about finished data; it must not be made
      // while loading is still true.
      await tester.pumpWidget(_async(loading: true, data: const <String>[]));
      await tester.pump();

      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.byType(AppEmpty), findsNothing);
      expect(find.text('Nothing here yet'), findsNothing);
    });

    testWidgets('empty data shows the designed empty state', (tester) async {
      await tester.pumpWidget(_async(loading: false, data: const <String>[]));
      await tester.pump();

      expect(find.byType(AppEmpty), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.byType(AppSkeleton), findsNothing);
    });

    testWidgets('data shows content', (tester) async {
      await tester.pumpWidget(
        _async(loading: false, data: const ['Winter fuel', 'School kits']),
      );
      await tester.pump();

      expect(find.text('Winter fuel'), findsOneWidget);
      expect(find.text('School kits'), findsOneWidget);
      expect(find.byType(AppEmpty), findsNothing);
      expect(find.byType(AppErrorState), findsNothing);
    });

    testWidgets('error shows the error state and never a dead end', (
      tester,
    ) async {
      var retried = 0;
      await tester.pumpWidget(
        _async(
          loading: false,
          error: 'You appear to be offline.',
          data: null,
          onRetry: () => retried++,
        ),
      );
      await tester.pump();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('You appear to be offline.'), findsOneWidget);

      // The recovery path must actually work — an error with a retry that
      // does nothing is still a dead end.
      await tester.tap(find.text('retry'));
      await tester.pumpAndSettle();
      expect(retried, 1);
    });

    testWidgets('error keeps already-loaded content visible', (tester) async {
      await tester.pumpWidget(
        _async(
          loading: false,
          error: 'Connection lost.',
          data: const ['Winter fuel'],
        ),
      );
      await tester.pump();

      expect(find.byType(AppErrorState), findsOneWidget);
      // Stale but readable — better than wiping the screen for an offline
      // user, which is what the app did before.
      expect(find.text('Winter fuel'), findsOneWidget);
      expect(find.byType(Opacity), findsWidgets);
    });

    testWidgets('a background refresh does not flash the skeleton', (
      tester,
    ) async {
      // loading true WITH data present = a silent refresh. The console's
      // pollSilent behaviour, preserved.
      await tester.pumpWidget(
        _async(loading: true, data: const ['Winter fuel']),
      );
      await tester.pump();

      expect(find.byType(AppSkeleton), findsNothing);
      expect(find.text('Winter fuel'), findsOneWidget);
    });
  });

  group('AppRow', () {
    testWidgets('renders title, meta, progress and a trailing amount', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AppRow(
            title: 'Winter fuel',
            meta: '42 families',
            progress: 0.64,
            progressStart: '6,400,000',
            progressEnd: '64%',
            trailing: AppRowAmount(
              amount: '50,000',
              status: 'Pending',
              tone: AppStatusTone.pending,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Winter fuel'), findsOneWidget);
      expect(find.text('42 families'), findsOneWidget);
      expect(find.text('6,400,000'), findsOneWidget);
      expect(find.text('50,000'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.64, 0.001));
    });

    testWidgets('progress is clamped rather than overflowing', (tester) async {
      await tester.pumpWidget(
        _host(const AppRow(title: 'Over-funded', progress: 1.8)),
      );
      await tester.pump();

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1.0);
    });

    testWidgets('status is a word, not colour alone', (tester) async {
      // Colour-blind users and greyscale screenshots both need the word.
      await tester.pumpWidget(
        _host(
          const AppStatusTag(label: 'Delivered', tone: AppStatusTone.settled),
        ),
      );
      await tester.pump();
      expect(find.text('DELIVERED'), findsOneWidget);
    });
  });

  group('right-to-left', () {
    testWidgets('the row mirrors without any direction-specific override', (
      tester,
    ) async {
      Future<Offset> titleOffset(TextDirection d) async {
        await tester.pumpWidget(
          _host(
            const AppRow(
              title: 'Winter fuel',
              trailing: AppRowAmount(amount: '50,000'),
            ),
            direction: d,
          ),
        );
        await tester.pump();
        return tester.getTopLeft(find.text('Winter fuel'));
      }

      final ltr = await titleOffset(TextDirection.ltr);
      final rtl = await titleOffset(TextDirection.rtl);

      // Under RTL the title starts further right, because the trailing
      // amount has moved to the left. If this fails, a physical EdgeInsets or
      // Alignment has crept back in.
      expect(
        rtl.dx,
        greaterThan(ltr.dx),
        reason:
            'The row did not mirror — check for physical left/right '
            'values instead of EdgeInsetsDirectional / AlignmentDirectional.',
      );
    });
  });

  group('dark theme', () {
    testWidgets('widgets resolve the dark palette', (tester) async {
      await tester.pumpWidget(
        _host(const AppRow(title: 'Winter fuel'), brightness: Brightness.dark),
      );
      await tester.pump();

      final text = tester.widget<Text>(find.text('Winter fuel'));
      expect(
        text.style?.color,
        AppColors.dark.ink,
        reason:
            'The row must read its colour from the resolved palette, not '
            'from a hardcoded constant.',
      );
    });
  });
}
