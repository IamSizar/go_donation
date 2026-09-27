// Client note: every upload button only ever opened the gallery — no way to
// take a new picture and have it uploaded on the spot. This pins the sheet
// `pickCroppedImage` now shows first: [chooseImageSource] in image_pick.dart.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/shared/utils/image_pick.dart';

Widget _wrap(Widget home) => GetMaterialApp(
  translations: AppTranslations(),
  locale: AppLocaleService.english,
  fallbackLocale: AppLocaleService.english,
  supportedLocales: AppLocaleService.supportedLocales,
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

void main() {
  tearDown(Get.reset);

  testWidgets('tapping "Take Photo" resolves to the camera source', (
    tester,
  ) async {
    late Future<ImageSource?> result;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => result = chooseImageSource(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    expect(await result, ImageSource.camera);
    Get.reset();
  });

  testWidgets('tapping "Choose from Gallery" resolves to the gallery source', (
    tester,
  ) async {
    late Future<ImageSource?> result;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => result = chooseImageSource(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from Gallery'));
    await tester.pumpAndSettle();
    expect(await result, ImageSource.gallery);
    Get.reset();
  });

  testWidgets('dismissing the sheet without a choice resolves to null', (
    tester,
  ) async {
    late Future<ImageSource?> result;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => result = chooseImageSource(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Tap the scrim above the sheet to dismiss it, same as a real back-tap.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(await result, isNull);
    Get.reset();
  });

  testWidgets('reads correctly in Arabic (RTL)', (tester) async {
    late Future<ImageSource?> result;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: AppLocaleService.arabic,
        fallbackLocale: AppLocaleService.english,
        supportedLocales: AppLocaleService.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => result = chooseImageSource(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('التقاط صورة'), findsOneWidget);
    expect(find.text('اختيار من المعرض'), findsOneWidget);
    await tester.tap(find.text('التقاط صورة'));
    await tester.pumpAndSettle();
    expect(await result, ImageSource.camera);
    Get.reset();
  });
}
