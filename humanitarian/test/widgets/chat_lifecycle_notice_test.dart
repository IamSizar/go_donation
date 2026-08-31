// Does a participant actually LEARN why their chat stopped working?
//
// The server refuses a message in a paused or ended thread. The app's job is
// to say so before they type — and to say it in their own language, with the
// staff member's reason, rather than showing a composer that leads to a
// snackbar. These tests pin exactly that: the notice appears, it explains, it
// carries the reason, and it stays out of the way of a healthy chat.
//
// The four locales are checked because the strings are new, and a new string
// that exists only in English is the failure this project's localization
// rules exist to prevent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_lifecycle_notice.dart';

/// Pumps the notice inside the app's real translation stack, in `locale`.
Future<void> pumpNotice(
  WidgetTester tester, {
  required String lifecycle,
  String? reason,
  Locale locale = const Locale('en', 'US'),
}) async {
  await tester.pumpWidget(
    GetMaterialApp(
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      home: Scaffold(
        body: ChatLifecycleNotice(lifecycle: lifecycle, reason: reason),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('an open chat shows no notice at all', (tester) async {
    await pumpNotice(tester, lifecycle: ChatLifecycle.open);
    // Nothing rendered: the composer keeps its place.
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a paused chat explains that it is temporary', (tester) async {
    await pumpNotice(tester, lifecycle: ChatLifecycle.paused);
    expect(
      find.text('This conversation has been paused by our team.'),
      findsOneWidget,
    );
    // "You can still read it" is the part that stops a user thinking the
    // history is gone.
    expect(
      find.textContaining('You can still read it'),
      findsOneWidget,
    );
  });

  testWidgets('an ended chat says it is closed, not paused', (tester) async {
    await pumpNotice(tester, lifecycle: ChatLifecycle.ended);
    expect(
      find.text('This conversation has been closed by our team.'),
      findsOneWidget,
    );
    expect(
      find.text('This conversation has been paused by our team.'),
      findsNothing,
    );
  });

  testWidgets("the staff member's reason is shown verbatim", (tester) async {
    await pumpNotice(
      tester,
      lifecycle: ChatLifecycle.paused,
      reason: 'Under review by our team',
    );
    expect(find.textContaining('Under review by our team'), findsOneWidget);
    expect(find.textContaining('Reason'), findsOneWidget);
  });

  testWidgets('a blank reason is not rendered as an empty line', (tester) async {
    await pumpNotice(tester, lifecycle: ChatLifecycle.paused, reason: '   ');
    expect(find.textContaining('Reason'), findsNothing);
  });

  testWidgets('every locale gets a translated notice, not English', (
    tester,
  ) async {
    // en is the source; the other three must differ from it or the string was
    // never actually translated.
    const english = 'This conversation has been paused by our team.';
    for (final locale in const [
      Locale('ar', 'SA'),
      Locale('ar', 'IQ'), // Sorani
      Locale('ar', 'TR'), // Badini
    ]) {
      await pumpNotice(
        tester,
        lifecycle: ChatLifecycle.paused,
        locale: locale,
      );
      expect(
        find.text(english),
        findsNothing,
        reason: 'the paused notice fell back to English in $locale',
      );
    }
  });

  testWidgets('the notice mirrors in RTL', (tester) async {
    await pumpNotice(
      tester,
      lifecycle: ChatLifecycle.paused,
      locale: const Locale('ar', 'SA'),
    );
    // Logical padding only — an EdgeInsets.fromSTEB-style directional inset is
    // what makes the icon sit on the correct side in Arabic.
    final container = tester.widget<Container>(
      find.byType(Container).first,
    );
    expect(container.padding, isA<EdgeInsetsDirectional>());
  });
}
