// Guards the Events-hub/group card subtitles against silent truncation in
// English at small device widths (chunk 14).
//
// THE DEFECT
// The "boxes must always be the same size" fix (chunk 9,
// event_hub_card_equal_height_test.dart) reserves a fixed number of lines
// for each card's title/subtitle box, sized off a TextPainter at the
// widget's own `maxLines`. That fix is correct and must stay — but the
// reserved line count was tuned against the Arabic copy for these cards.
// On a physical 720x1600 (360dp-wide) device in ENGLISH, the "Event
// services" hub card's subtitle — "Book halls, photographers, and
// everything your event needs" — is long enough that it still overflows
// the reserved 3 lines and gets cut with an ellipsis, even though the
// Arabic subtitle for the same card fits comfortably, and even though the
// sibling "Events section" card's English subtitle fits fine.
//
// WHY THIS TEST LOADS A REAL FONT
// Headless `flutter test` has no Android/iOS system font registered, so
// unstyled text falls back to a generic host substitute whose glyphs run
// roughly 2x wider than Roboto (measured: ~12px/char at 12.5sp here, vs
// Roboto's ~6.5px/char). Asserting truncation against that substitute
// produces false positives on strings that are known-fine on a real
// device (verified below against the "Events section" subtitle, which the
// bug report confirms fits). So this file loads the real Roboto-Regular
// font (test/fixtures/Roboto-Regular.ttf, Apache-2.0, Google) and forces
// the widget tree to use it, so wrapping here approximates the Android
// device the bug was reported on instead of the host's substitute font.
//
// THIS TEST
// Mounts every hub/group card subtitle actually shipped (see
// marriage_hub_screen.dart and marriage_event_group_screen.dart) at a
// 360-logical-pixel-wide viewport — matching the physical device the bug
// was observed on — in English with Roboto loaded, and asserts none of
// them render with ellipsized (overflowing) text. Run against the pre-fix
// English copy this fails for "Event services"; shortening that one
// string is what makes it pass without touching Arabic or raising the
// reserved line count (which would undo the chunk-9 compaction).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marriage/widgets/event_hub_cards.dart';

/// Loads test/fixtures/Roboto-Regular.ttf into the engine under the family
/// name 'Roboto', so [_cardsApp] below (which forces that family via its
/// theme) measures text with real Android-like metrics instead of the
/// headless host's substitute font.
Future<void> _loadRobotoFont() async {
  final bytes = await File(
    'test/fixtures/Roboto-Regular.ttf',
  ).readAsBytes();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// Builds a screen shaped exactly like the real hub/group screens: a
/// [Scaffold] with the same 20px horizontal padding and a [CardGrid] with
/// the same `spacing`, hosting one [EventHubCard] per subtitle in
/// [subtitles] at the given [dense]-ness (dense == the 6-item group grids,
/// non-dense == the 2-card hub). Forces the 'Roboto' family loaded by
/// [_loadRobotoFont] onto the theme's text theme so EventHubCard's
/// fontFamily-less TextStyles inherit it from the ambient DefaultTextStyle.
Widget _cardsApp({required List<String> subtitles, required bool dense}) {
  final baseTheme = AppThemeConfig.buildTheme(Brightness.light);
  final robotoTheme = baseTheme.copyWith(
    textTheme: baseTheme.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: baseTheme.primaryTextTheme.apply(fontFamily: 'Roboto'),
  );
  return GetMaterialApp(
    theme: robotoTheme,
    translations: AppTranslations(),
    locale: const Locale('en', 'US'),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Builder(
          builder: (context) => CardGrid(
            spacing: dense ? 12 : 16,
            children: [
              for (final subtitle in subtitles)
                EventHubCard(
                  icon: Icons.celebration_outlined,
                  color: AppThemeConfig.accent(context),
                  title: 'Card title',
                  subtitle: subtitle,
                  onTap: () {},
                  dense: dense,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Asserts no subtitle [Text] widget currently on screen is rendering with
/// clipped (ellipsized) text — i.e. its [RenderParagraph] needed more
/// lines than its `maxLines` allowed. Every card in these test screens
/// shares the literal title "Card title" (never truncates: it's short),
/// so excluding that exact string scopes the guard to the subtitle copy
/// that actually varies per card and produced the reported bug — the
/// `.tr`-resolved English text, not the translation key passed in.
void _expectNoTruncatedSubtitle(WidgetTester tester) {
  for (final element in find.byType(Text).evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderParagraph) continue;
    final textWidget = element.widget as Text;
    if (textWidget.data == 'Card title') continue;
    expect(
      renderObject.didExceedMaxLines,
      isFalse,
      reason:
          'Subtitle "${textWidget.data}" is truncated (ellipsized) at '
          '360dp in English — the reserved-lines box in EventHubCard is '
          'too short for this copy.',
    );
  }
}

void main() {
  setUpAll(_loadRobotoFont);
  setUp(Get.reset);
  tearDown(Get.reset);

  // Every subtitle the hub's two top-level cards ship in English
  // (marriage_hub_screen.dart).
  // These are the translation KEYS used verbatim in
  // marriage_hub_screen.dart / marriage_event_group_screen.dart — passed
  // to EventHubCard, which resolves them with `.tr` through
  // AppTranslations exactly as production does. Using the keys (not the
  // resolved English text) here exercises the same lookup path.
  const hubSubtitles = [
    'Book halls, photographers, and everything your event needs',
    'Profiles, posts, and support for the events community',
  ];

  // Every subtitle KEY the two group screens' item grids ship
  // (marriage_event_group_screen.dart) — both groups combined, since both
  // render at the same `dense: true` size and column width.
  const groupSubtitles = [
    'Request a hall for your event',
    'Request a photographer for your event',
    'Request a stage setup for your event',
    'Request decorations for your event',
    'Request tents and related equipment',
    'Request a service not listed above',
    'Search event profiles by name or gender',
    'News and stories from the events section',
    'View your profile and its status, or create one',
    'Upgrade your profile with a subscription package',
    'Staff-mediated conversations for accepted meetings',
    'Questions or issues about the events section',
  ];

  Future<void> pumpAt360(WidgetTester tester, Widget app) async {
    // 720x1600 physical @2x == 360x800 logical — the exact device the
    // ellipsis was observed on.
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'hub card subtitles do not truncate in English at 360dp width',
    (tester) async {
      await pumpAt360(
        tester,
        _cardsApp(subtitles: hubSubtitles, dense: false),
      );
      _expectNoTruncatedSubtitle(tester);
    },
  );

  testWidgets(
    'group item card subtitles do not truncate in English at 360dp width',
    (tester) async {
      await pumpAt360(
        tester,
        _cardsApp(subtitles: groupSubtitles, dense: true),
      );
      _expectNoTruncatedSubtitle(tester);
    },
  );
}
