// A Dio adapter that answers the featured-campaigns carousel.
//
// WHY THIS IS SEPARATE FROM FakeHttpOverrides
// The carousel is the one caller on Home that uses Dio rather than
// package:http, and the shared HttpOverrides fake implements only the two
// HttpClient members package:http touches. Everything else falls through to
// noSuchMethod and throws, so in every suite before this one the carousel sat
// in its error state — documented at length in role_dashboard_render_test.dart
// and accepted there, because that file measures other panels.
//
// A test that is ABOUT the campaign cards cannot accept it: an error banner
// has no cards to measure. Swapping Dio's adapter reaches only this client and
// leaves every other suite seeing exactly what it saw before.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class FakeCampaignsAdapter implements HttpClientAdapter {
  FakeCampaignsAdapter(this.body, {this.statusCode = 200});

  /// The JSON the carousel's endpoint should answer with.
  final String body;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// One campaign, with a two-line title — the tallest a card gets, which is the
/// case any height measurement has to be made against.
String fakeCampaignsJson({
  String title = 'حملة كسوة الشتاء للأسر النازحة في مخيمات أربيل',
  String location = 'أربيل - مخيم حرشم',
  int target = 5000000,
  int collected = 150000,
}) =>
    jsonEncode({
      'success': true,
      // The controller gates on this exact field, not on `success`.
      'status': 'success',
      'data': [
        {
          'id': 1,
          'title': title,
          'location': location,
          'target_amount': target,
          'collected_amount': collected,
          'status': 'active',
          'category': 'إغاثة',
        },
      ],
    });
