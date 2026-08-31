// Pins that the Events hub asks the server for its own slice of the feed.
//
// WHY THIS IS A SERVER-SIDE FILTER, AND WHY THAT NEEDS A TEST
// The owner asked for the activity posts and news published from the admin
// panel to appear on the Events hub, under the two cards. `GET /api/media`
// caps its result at 50 rows (clampLimit) and orders newest-first across
// EVERY post type, so fetching the general feed and dropping articles/videos
// in the client would quietly hide older activity posts behind newer posts of
// types the hub never renders — a feed that looks fine on a young database
// and silently truncates on a busy one. The fix is `?type=activity,news`, and
// this file pins the request the app actually puts on the wire, because the
// failure mode is invisible from the widget tree.
//
// The `type` param is also the ONLY thing separating the hub's feed from the
// full News & Activities feed, so an omitted param is a real regression: the
// hub would show marriage-adjacent articles and videos it was never meant to.
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
  test('the Events hub feed requests only activity posts and news', () async {
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
