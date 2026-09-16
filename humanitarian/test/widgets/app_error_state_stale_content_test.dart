// Pins how AppErrorState lays out content it keeps on screen after a refresh
// failed — OPOS #26349.
//
// WHAT IS PINNED
//   1. Inside a scroll view (unbounded height) the error banner and the dimmed
//      stale content both show, and nothing throws. AppErrorState used to wrap
//      the stale content in an Expanded unconditionally, which asserts
//      ("non-zero flex but incoming height constraints are unbounded") the
//      moment a screen places AppAsync inside a ListView — as the Messages tab
//      does with its thread list.
//   2. Inside a bounded area — the common placement, AppAsync in an Expanded —
//      the stale content still takes the rest of the height, exactly as before.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

const _staleText = 'Stale row';

/// Pumps [body] in a themed app, the way every screen hosts AppErrorState.
Future<void> _pump(WidgetTester tester, Widget body) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      home: Scaffold(body: body),
    ),
  );
}

/// An error state holding real rows that are now possibly out of date.
AppErrorState _errorWithStaleRows({Widget stale = const Text(_staleText)}) =>
    AppErrorState(message: 'Could not refresh.', onRetry: () {}, staleContent: stale);

void main() {
  testWidgets('stale content inside a scroll view shows, and nothing throws', (
    tester,
  ) async {
    await _pump(tester, ListView(children: [_errorWithStaleRows()]));

    expect(
      tester.takeException(),
      isNull,
      reason: 'an Expanded inside an unbounded scroll view asserts',
    );
    expect(find.text('Could not refresh.'), findsOneWidget);
    expect(find.text(_staleText), findsOneWidget);
  });

  testWidgets('in a bounded area the stale content still takes the rest of the '
      'height', (tester) async {
    await _pump(
      tester,
      Column(
        children: [
          Expanded(
            child: _errorWithStaleRows(stale: const SizedBox.expand()),
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    final staleHeight = tester
        .getSize(find.byType(Opacity).last)
        .height;
    expect(
      staleHeight,
      greaterThan(200),
      reason: 'the dimmed rows should fill the space below the banner',
    );
  });
}
