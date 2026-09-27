// deep_link_router.dart — what happens when a shared link is tapped.
//
// THE BUG THIS FIXES (client report)
// The share button on a post/campaign put nothing but plain text on the
// clipboard/share-sheet — `appShareUrl` (app_share.dart) was empty, so
// `withAppLink` appended no link at all. Some share targets then ran a web
// search on the plain text instead of opening anything, which is what looked
// like "the share button leads to Google".
//
// THE FIX
// Every specific-thing share (a campaign, a marriage profile, a media post)
// now appends a `balancenex://open?type=...&id=...` link (see
// core/app_share.dart's `deepLink`). This file is the other half: it listens
// for that scheme being opened — the app cold-started by it, or already
// running and handed it while backgrounded — and reuses the EXACT SAME
// destination-resolution and navigation this app already trusts for push
// notifications (notification_destination.dart / notification_navigator.dart)
// rather than inventing a second router. A deep link and a push notification
// are the same kind of event — "take me to entity X" — so one decision table
// serves both; see notification_destination.dart's own header for why that
// table is deliberately a closed, tested set of destinations.
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/modules/notifications/utils/notification_destination.dart';
import 'package:flutter_application_1/modules/notifications/utils/notification_navigator.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:get/get.dart';

abstract final class DeepLinkRouter {
  static final _appLinks = AppLinks();

  /// Subscribes both link paths. Call once, from main(), after runApp() has
  /// been scheduled — mirrors PushTapRouter.wire() exactly.
  static void wire() {
    // Opened while the app was already running (foreground or background).
    _appLinks.uriLinkStream.listen((uri) {
      debugPrint('[deeplink] opened (live) uri=$uri');
      _handleUri(uri);
    });

    // The link that launched a killed process, delivered once at startup.
    _appLinks.getInitialLink().then((uri) {
      if (uri == null) return; // a normal launch, not a link
      debugPrint('[deeplink] opened (cold start) uri=$uri');
      _handleUri(uri);
    });
  }

  static Future<void> _handleUri(Uri uri) async {
    // Only ever balancenex://open?type=...&id=... — anything else (a future
    // scheme use, a malformed link) is silently ignored rather than guessed
    // at, same posture as resolveNotificationDestination's own unknown-input
    // handling.
    if (uri.scheme != 'balancenex' || uri.host != 'open') return;
    final data = <String, dynamic>{
      'related_entity_type': uri.queryParameters['type'],
      'related_entity_id': uri.queryParameters['id'],
    };
    final destination = resolveNotificationDestination(
      data,
      isGuest: isGuestMode,
    );
    if (!await _waitForShell()) return;
    await openNotificationDestinationFromTray(destination);
  }

  /// Identical wait to PushTapRouter's — a link that arrives before the app
  /// has left the splash/auth flow has nowhere safe to land yet.
  static Future<bool> _waitForShell() async {
    for (var attempt = 0; attempt < 30; attempt++) {
      final route = Get.currentRoute;
      if (route == AppRoutes.home) return true;
      if (route != AppRoutes.splash && route.isNotEmpty) {
        debugPrint('[deeplink] not opened: app is on $route');
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('[deeplink] not opened: app never reached the shell');
    return false;
  }
}
