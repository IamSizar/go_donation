// Pins the cascading city → district → sub-district pickers (migration 136).
//
// The dashboard manages cities, districts (أقضية) and sub-districts (نواحي)
// under the fixed 18 governorates; the forms show each level only when staff
// have entered something for it, district and sub-district are optional, and
// the STORED value is the place's Arabic name whatever language the person
// reads — so the dashboard sees one word for one place.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/auth/widgets/area_picker.dart';

Map<String, dynamic> _area(int id, String level, String ar, String en, {int? parent}) => {
  'id': id,
  'governorate': 'Nineveh',
  'parent_id': parent,
  'level': level,
  'name_en': en,
  'name_ar': ar,
  'name_ckb': '',
  'name_kmr': '',
  'display_order': id,
  'active': true,
  'children': 0,
};

final _nineveh = [
  _area(1, 'city', 'الموصل', 'Mosul'),
  _area(2, 'city', 'تلعفر', 'Tel Afar'),
  _area(11, 'district', 'قضاء الموصل', 'Mosul District', parent: 1),
  _area(21, 'subdistrict', 'حمام العليل', 'Hammam al-Alil', parent: 11),
];

/// Answers /areas per governorate; counts requests so caching can be pinned.
int _requests = 0;
ModuleApi _api({bool fail = false}) => ModuleApi(
  httpClient: MockClient((request) async {
    _requests++;
    if (fail) return http.Response('oops', 500);
    final gov = request.url.queryParameters['governorate'];
    final items = gov == 'Nineveh' ? _nineveh : <Map<String, dynamic>>[];
    return http.Response(
      jsonEncode({'success': true, 'items': items}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

class _Harness extends StatefulWidget {
  const _Harness({required this.governorate});
  final String governorate;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String city = '', district = '', subdistrict = '';
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      children: [
        Text('value:$city|$district|$subdistrict'),
        AreaPicker(
          governorate: widget.governorate,
          city: city,
          district: district,
          subdistrict: subdistrict,
          cityLabel: const Text('CITY'),
          onChanged: (c, d, s) => setState(() {
            city = c;
            district = d;
            subdistrict = s;
          }),
        ),
      ],
    ),
  );
}

Future<void> _pump(WidgetTester tester, String governorate, Locale locale) async {
  await tester.pumpWidget(
    GetMaterialApp(
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      home: Scaffold(body: _Harness(governorate: governorate)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String hint, String option) async {
  await tester.tap(find.text(hint));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _requests = 0;
    AreaDirectory.instance.resetForTest();
  });

  testWidgets('city → district → sub-district cascade, storing Arabic names', (tester) async {
    AreaDirectory.instance.api = _api();
    // English reader: labels in English, stored values still Arabic.
    await _pump(tester, 'Nineveh', const Locale('en', 'US'));

    expect(find.text('CITY'), findsOneWidget);
    // No district field until a city with districts is picked.
    expect(find.text('Choose the district'), findsNothing);

    await _pick(tester, 'Choose your city', 'Mosul');
    expect(find.text('value:الموصل||'), findsOneWidget);
    expect(find.text('Choose the district'), findsOneWidget);

    await _pick(tester, 'Choose the district', 'Mosul District');
    expect(find.text('value:الموصل|قضاء الموصل|'), findsOneWidget);

    await _pick(tester, 'Choose the sub-district', 'Hammam al-Alil');
    expect(find.text('value:الموصل|قضاء الموصل|حمام العليل'), findsOneWidget);

    // Picking another city clears the levels under it, and a city with no
    // districts shows no district field at all.
    await tester.tap(find.text('Mosul'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tel Afar').last);
    await tester.pumpAndSettle();
    expect(find.text('value:تلعفر||'), findsOneWidget);
    expect(find.text('Choose the district'), findsNothing);

    // One request for the governorate, however many rebuilds.
    expect(_requests, 1);
  });

  testWidgets('district is optional: it can be un-picked again', (tester) async {
    AreaDirectory.instance.api = _api();
    await _pump(tester, 'Nineveh', const Locale('en', 'US'));
    await _pick(tester, 'Choose your city', 'Mosul');
    await _pick(tester, 'Choose the district', 'Mosul District');
    await tester.tap(find.text('Mosul District'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('— None —').last);
    await tester.pumpAndSettle();
    expect(find.text('value:الموصل||'), findsOneWidget);
    expect(find.textContaining('(optional)', findRichText: true), findsWidgets);
  });

  testWidgets('a governorate with no cities renders nothing (free-text city stays)', (tester) async {
    AreaDirectory.instance.api = _api();
    await _pump(tester, 'Basra', const Locale('en', 'US'));
    expect(find.text('CITY'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(AreaDirectory.instance.peek('Basra')?.hasCities, isFalse);
  });

  testWidgets('a failed load says so and retries', (tester) async {
    AreaDirectory.instance.api = _api(fail: true);
    await _pump(tester, 'Nineveh', const Locale('en', 'US'));
    expect(find.text('Could not load the city list.'), findsOneWidget);

    AreaDirectory.instance.api = _api();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('CITY'), findsOneWidget);
  });

  testWidgets('Arabic reader sees Arabic names', (tester) async {
    AreaDirectory.instance.api = _api();
    await _pump(tester, 'Nineveh', const Locale('ar', 'SA'));
    await _pick(tester, 'اختر مدينتك', 'الموصل');
    expect(find.text('value:الموصل||'), findsOneWidget);
    expect(find.text('اختر القضاء'), findsOneWidget);
  });
}
