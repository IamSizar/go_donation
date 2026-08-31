// Guards the Events-hub "boxes must always be the same size" bug (chunk 9).
//
// THE DEFECT
// CardGrid (see event_hub_cards.dart) is a Wrap so that rows hug their
// tallest content instead of a fixed aspect-ratio cell — that fix is
// correct and must stay (see the dead-space regression test in
// marriage_hub_events_grid_test.dart). But a Wrap sizes each CHILD to its
// own content too: with `Column(mainAxisSize: MainAxisSize.min)`, a card
// whose subtitle happens to wrap onto three lines renders taller than a
// sibling whose subtitle only needs two. That is exactly what the owner
// reported from a screenshot — "قسم الفعاليات" (a three-line subtitle) was
// visibly taller than "خدمات الفعاليات" (two lines).
//
// THIS TEST
// Deliberately mismatched subtitle lengths — one short, one long enough to
// wrap to the card's full maxLines — inside one CardGrid, then asserts
// every card renders at the exact same height. Run against the
// pre-fix code (Text with no reserved height) this fails; the fix reserves
// `maxLines` worth of height for the title and subtitle boxes regardless of
// actual content length, which is what makes it pass.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marriage/widgets/event_hub_cards.dart';

Widget _app(WidgetBuilder builder) => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Builder(builder: builder),
    ),
  ),
);

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  testWidgets(
    'every card in a CardGrid renders at the same height, even with '
    'wildly uneven subtitle lengths',
    (tester) async {
      await tester.pumpWidget(
        _app(
          (context) => CardGrid(
            children: [
              // Short enough to stay on one line.
              EventHubCard(
                icon: Icons.celebration_outlined,
                color: AppThemeConfig.accent(context),
                title: 'Short',
                subtitle: 'One line',
                onTap: () {},
              ),
              // Long enough to wrap to the full 3-line maxLines this
              // (non-dense) card allows.
              EventHubCard(
                icon: Icons.groups_outlined,
                color: AppThemeConfig.accent(context),
                title: 'Long',
                subtitle:
                    'This subtitle is deliberately long enough that it '
                    'must wrap across three separate lines inside the card',
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cards = find.byType(EventHubCard);
      expect(cards, findsNWidgets(2));

      final shortHeight = tester.getSize(cards.at(0)).height;
      final longHeight = tester.getSize(cards.at(1)).height;

      expect(
        shortHeight,
        longHeight,
        reason:
            'a one-line subtitle card and a three-line subtitle card must '
            'render at the same height — this is the owner-reported '
            '"boxes must always be the same size" bug',
      );
    },
  );

  testWidgets(
    'dense cards (the 6-item group grids) are also equal height under '
    'uneven subtitles',
    (tester) async {
      await tester.pumpWidget(
        _app(
          (context) => CardGrid(
            spacing: 12,
            children: [
              EventHubCard(
                icon: Icons.search_rounded,
                color: AppThemeConfig.accent(context),
                title: 'A',
                subtitle: 'Short',
                onTap: () {},
                dense: true,
              ),
              EventHubCard(
                icon: Icons.forum_outlined,
                color: AppThemeConfig.accent(context),
                title: 'B',
                subtitle:
                    'Staff-mediated conversations for accepted meetings',
                onTap: () {},
                dense: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cards = find.byType(EventHubCard);
      expect(cards, findsNWidgets(2));

      final first = tester.getSize(cards.at(0)).height;
      final second = tester.getSize(cards.at(1)).height;
      expect(first, second);
    },
  );
}
