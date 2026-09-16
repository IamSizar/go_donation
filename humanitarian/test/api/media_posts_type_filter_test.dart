// Pins the `?type=` query that ModuleApi.mediaPosts builds: a post-type filter
// goes on the request, and the general feed sends none.
//
// WHY THE FILTER IS SERVER-SIDE
// `GET /api/media` caps its result at 50 rows (clampLimit) and orders
// newest-first across EVERY post type. Fetching the general feed and dropping
// unwanted types in the client would quietly hide older posts of the wanted
// types behind newer posts of the rest: a feed that looks fine on a young
// database and silently truncates on a busy one. The filter has to travel as
// `?type=`, and that failure is invisible from the widget tree, so this file
// pins the request the app actually puts on the wire.
//
// SCOPE. Only mediaPosts is called here. Filtered feeds reach the server
// through MediaPostsController(postType:) and ModuleApi.mediaPostsPage, which
// no test in this file covers. The Events hub's news feed ("activity,news")
// was one until PR #76 (commit 33d6891, OPOS #25858) removed it.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/api/module_api.dart';

/// Captures the URI of the single GET the call under test performs, and
/// answers with a well-formed empty feed so the call completes normally.
Future<Uri> _capturedUri(Future<void> Function(ModuleApi api) call) async {
  late Uri seen;
  final api = ModuleApi(
    httpClient: MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({'success': true, 'items': <dynamic>[]}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  await call(api);
  return seen;
}

void main() {
  test('a post-type filter is sent as the type query parameter', () async {
    final uri = await _capturedUri(
      (api) => api.mediaPosts(type: 'activity,news'),
    );

    // Read the decoded value, not the raw query string: the comma may be
    // percent-encoded on the wire, and the server splits the decoded value.
    expect(uri.queryParameters['type'], 'activity,news');
  });

  test('the general feed sends no type, so the server picks the default', () async {
    // Without ?type= the server serves every type EXCEPT `marriage`
    // (listings.go). Sending an empty type= instead would filter on the
    // empty string and match no row at all — an empty News screen.
    final uri = await _capturedUri((api) => api.mediaPosts());

    expect(uri.queryParameters.containsKey('type'), isFalse);
  });

  test('a blank type is treated as no filter, not as an empty filter', () async {
    final uri = await _capturedUri((api) => api.mediaPosts(type: '   '));

    expect(uri.queryParameters.containsKey('type'), isFalse);
  });
}
