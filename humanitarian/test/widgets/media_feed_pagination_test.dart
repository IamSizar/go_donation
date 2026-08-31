// Pins how the News & Activities feed walks the archive.
//
// WHY THIS FILE EXISTS
// GET /api/media used to return the newest 50 posts and nothing else, so every
// older post was unreachable unless the reader guessed a word inside it. The
// endpoint now pages with an opaque `?cursor=`, and the feed follows it. Two
// failure modes are worth a test because neither is visible from the widget
// tree:
//
//  1. PAGING THAT DOES NOT RESET. The reader types a new search while the old
//     query's cursor is still held. Page 2 of "winter" then arrives carrying a
//     cursor minted for the unfiltered feed, and the results of two different
//     queries are stitched into one list. On screen it looks like a feed.
//
//  2. PAGING THAT NEVER STOPS. At the end of the archive the server sends no
//     `next_cursor`. A client that instead guesses "the page was full, so ask
//     again" keeps hammering the endpoint at the bottom of every feed whose
//     length happens to divide by the page size.
//
// Both are assertions about the REQUESTS, so the fake HTTP layer records URLs
// and the tests read those rather than the rendered list.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';

import '../support/fake_http.dart';

/// A one-post page that promises another one after it.
const _pageWithMore =
    '{"success": true, "items": [{"id": 9, "title": "A"}], '
    '"next_cursor": "CURSOR-1"}';

/// The last page of the archive: no `next_cursor` at all.
const _lastPage = '{"success": true, "items": [{"id": 9, "title": "A"}]}';

void _installHttp(FakeHttpOverrides overrides) {
  final previous = HttpOverrides.current;
  HttpOverrides.global = overrides;
  addTearDown(() => HttpOverrides.global = previous);
}

List<Uri> _mediaRequests(FakeHttpOverrides overrides) => overrides.requestUrls
    .where((u) => u.path.contains('/api/media') && !u.path.contains('categor'))
    .toList(growable: false);

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({'id_user': '7'});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  testWidgets('changing the search term restarts paging from the newest post', (
    tester,
  ) async {
    final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: _pageWithMore);
    _installHttp(overrides);
    final controller = Get.put(MediaPostsController());
    await tester.pumpAndSettle();

    // Walk one page into the unfiltered archive, so a cursor is being held.
    await controller.loadMorePosts();
    await tester.pumpAndSettle();
    expect(
      _mediaRequests(overrides).last.queryParameters['cursor'],
      'CURSOR-1',
      reason: 'the feed did not follow the cursor into the archive',
    );

    await controller.setSearchQuery('winter');
    await tester.pumpAndSettle();

    final last = _mediaRequests(overrides).last;
    expect(last.queryParameters['q'], 'winter');
    expect(
      last.queryParameters.containsKey('cursor'),
      isFalse,
      reason:
          'the new search continued the OLD query cursor — page 2 of the '
          'unfiltered feed appended to page 1 of the search',
    );
    // ...and the results were replaced, not appended to what the previous
    // query had loaded.
    expect(controller.posts.length, 1);
  });

  testWidgets('the end of the archive stops the feed asking for more', (
    tester,
  ) async {
    final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: _lastPage);
    _installHttp(overrides);
    final controller = Get.put(MediaPostsController());
    await tester.pumpAndSettle();

    final afterFirstPage = _mediaRequests(overrides).length;
    expect(controller.hasMorePosts.value, isFalse);

    // Scrolling at the tail calls this on every notification, so it is called
    // repeatedly on purpose here.
    await controller.loadMorePosts();
    await controller.loadMorePosts();
    await controller.loadMorePosts();
    await tester.pumpAndSettle();

    expect(
      _mediaRequests(overrides).length,
      afterFirstPage,
      reason: 'the feed kept requesting pages past the end of the archive',
    );
    expect(controller.posts.length, 1, reason: 'the last page was duplicated');
  });

  testWidgets('a page is appended to the feed, not swapped in for it', (
    tester,
  ) async {
    final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: _pageWithMore);
    _installHttp(overrides);
    final controller = Get.put(MediaPostsController());
    await tester.pumpAndSettle();

    await controller.loadMorePosts();
    await tester.pumpAndSettle();

    expect(controller.posts.length, 2);
  });
}
