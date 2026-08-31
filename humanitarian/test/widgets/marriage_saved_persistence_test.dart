// Pins that a saved marriage profile STAYS saved, and that the saved list
// reachable from the feed's header agrees with the feed.
//
// THE BUG
// The owner reported that tapping save "doesn't go anywhere": leaving the
// screen and coming back showed the profile unsaved. The toggle always
// reached the server and the server always stored it — what was missing was
// the read back. The screen kept an in-memory `Set<int>` that started empty
// on every mount, so a fresh mount could only ever draw empty bookmarks.
//
// WHY THE OBVIOUS TEST WOULD NOT HAVE CAUGHT IT
// A test that taps save and then asserts the bookmark is filled passes
// against the BUGGY code — the in-memory set is correct for as long as the
// widget lives. The regression only shows on a FRESH mount, so the first test
// below never taps anything: it mounts a screen whose server already holds a
// bookmark and asserts the card renders saved.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_posts_screen.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_saved_screen.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_post_card.dart';

/// One feed row, trimmed to the fields the card actually reads.
Map<String, dynamic> _profile(int id) => {
  'id': id,
  'profile_code': 'P$id',
  'gender': 'male',
  'age': 30,
  'city': 'Erbil',
  'social_summary': 'Profile $id',
  // Empty, so the card draws its placeholder icon instead of reaching the
  // network for an image — widget tests serve no HTTP.
  'photo_url': '',
};

/// A fake server holding a bookmark set, exactly as the real one does: the
/// feed and the saved list are both served FROM it, and the toggle mutates
/// it. That is what lets one test assert the two views cannot disagree.
class _FakeServer {
  _FakeServer({required this.feed, Set<int>? saved, this.rejectToggle = false})
    : saved = saved ?? {};

  final List<int> feed;
  final Set<int> saved;

  /// When true the toggle endpoint refuses, so a test can watch the
  /// optimistic bookmark roll back instead of standing as a false save.
  final bool rejectToggle;

  /// Requests seen, so a test can assert the saved list was actually read.
  final requests = <String>[];

  ModuleApi get api => ModuleApi(httpClient: MockClient(_handle));

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    requests.add('${request.method} $path');
    List<Map<String, dynamic>> items;
    if (path.endsWith('/marriage/saved')) {
      items = [
        for (final id in feed)
          if (saved.contains(id)) _profile(id),
      ];
    } else if (path.endsWith('/save')) {
      if (rejectToggle) {
        return _json({'success': false, 'error': 'nope'});
      }
      final id = int.parse(path.split('/')[path.split('/').length - 2]);
      final nowSaved = !saved.contains(id);
      nowSaved ? saved.add(id) : saved.remove(id);
      return _json({'success': true, 'saved': nowSaved});
    } else {
      // The feed itself. `before_id` means a pagination page: answer empty so
      // the list does not grow forever under a scroll.
      items = request.url.queryParameters.containsKey('before_id')
          ? const []
          : [for (final id in feed) _profile(id)];
    }
    return _json({'success': true, 'items': items});
  }

  http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

Widget _app(Widget home) => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: home,
);

/// Lets both in-flight fetches (feed + saved list) settle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// True when the card for [profileId] draws a FILLED bookmark.
bool _isSaved(WidgetTester tester, int profileId) {
  final card = tester
      .widgetList<MarriagePostCard>(find.byType(MarriagePostCard))
      .firstWhere((c) => (c.profile['id'] as num).toInt() == profileId);
  return card.saved;
}

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();

    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(430, 2400);
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    addTearDown(binding.platformDispatcher.views.first.resetPhysicalSize);
    addTearDown(binding.platformDispatcher.views.first.resetDevicePixelRatio);
  });
  tearDown(Get.reset);

  testWidgets('a save made before this mount is drawn as saved', (
    tester,
  ) async {
    // NOTHING is tapped in this test. The bookmark exists only on the server,
    // which is precisely the situation the bug got wrong.
    final server = _FakeServer(feed: [1, 2], saved: {2});

    await tester.pumpWidget(_app(MarriagePostsScreen(api: server.api)));
    await _settle(tester);

    expect(_isSaved(tester, 2), isTrue, reason: 'the server holds this save');
    expect(_isSaved(tester, 1), isFalse);
    expect(server.requests, contains('GET /api/marriage/saved'));
  });

  testWidgets('unsaving in the saved list is reflected in the feed', (
    tester,
  ) async {
    final server = _FakeServer(feed: [1, 2], saved: {1, 2});

    await tester.pumpWidget(_app(MarriagePostsScreen(api: server.api)));
    await _settle(tester);
    expect(_isSaved(tester, 1), isTrue);

    // Open the saved list from the header button the owner asked for.
    await tester.tap(find.byTooltip('Saved'));
    await _settle(tester);
    expect(find.byType(MarriageSavedScreen), findsOneWidget);
    expect(find.byType(MarriagePostCard), findsNWidgets(2));

    // Unsave the first row from inside the saved list: it must leave here...
    final inSaved = find.descendant(
      of: find.byType(MarriageSavedScreen),
      matching: find.byType(IconButton),
    );
    await tester.tap(inSaved.first);
    await _settle(tester);
    expect(find.byType(MarriagePostCard), findsOneWidget);
    expect(server.requests, contains('POST /api/marriage/1/save'));

    // ...and the feed underneath must not still claim it is saved.
    Get.back();
    await _settle(tester);
    expect(_isSaved(tester, 1), isFalse);
    expect(_isSaved(tester, 2), isTrue);
  });

  testWidgets('a save the server refuses does not stay on screen', (
    tester,
  ) async {
    final server = _FakeServer(feed: [1], rejectToggle: true);

    await tester.pumpWidget(_app(MarriagePostsScreen(api: server.api)));
    await _settle(tester);
    expect(_isSaved(tester, 1), isFalse);

    await tester.tap(
      find.descendant(
        of: find.byType(MarriagePostCard),
        matching: find.byType(IconButton),
      ),
    );
    await _settle(tester);

    // The optimistic fill must be gone again: a bookmark left filled here
    // would be the very "my save went nowhere" confusion, one visit later.
    expect(_isSaved(tester, 1), isFalse);

    // Let the failure snackbar finish; its timer would otherwise outlive the
    // tree and trip the binding's pending-timer assertion.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('the saved list shows its empty state when nothing is saved', (
    tester,
  ) async {
    final server = _FakeServer(feed: [1], saved: {});

    await tester.pumpWidget(_app(MarriageSavedScreen(api: server.api)));
    await _settle(tester);

    expect(find.byType(AppEmpty), findsOneWidget);
    // The designed empty state, not a bare "nothing here": it says what to do.
    expect(
      find.text(
        'Nothing saved yet. Tap the bookmark on a profile to keep it here.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the header button reaches a 44pt tap target', (tester) async {
    final server = _FakeServer(feed: [1]);

    await tester.pumpWidget(_app(MarriagePostsScreen(api: server.api)));
    await _settle(tester);

    final size = tester.getSize(find.byTooltip('Saved'));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
