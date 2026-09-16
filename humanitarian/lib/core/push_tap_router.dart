// push_tap_router.dart — what happens when someone taps a notification in the
// phone's notification tray.
//
// THE BUG THIS FIXES (client report, 2026-09-16)
// Tapping a push opened the app at home and left the person to find the
// conversation themselves. main() subscribed to onMessageOpenedApp and only
// printed a debug line; the cold-start tap — the one that LAUNCHES the app
// from killed, delivered once via getInitialMessage() — was not handled at
// all, so it could not even have printed.
//
// TWO PATHS, ONE DECISION
//   • onMessageOpenedApp    — a stream. Fires for every tap while the process
//     is alive but backgrounded.
//   • getInitialMessage()   — a Future, resolved ONCE at startup with the
//     message whose tap started the process (null on a normal launch). It is
//     NOT re-delivered on the stream, which is why it is easy to miss and why
//     forgetting it leaves exactly the "cold tap goes to home" symptom.
// Both hand the message's `data` to the same handler, which asks
// resolveNotificationDestination where to go. No routing lives here.
//
// Sits beside push_registration.dart, which owns the token half of messaging.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/modules/notifications/utils/notification_destination.dart';
import 'package:flutter_application_1/modules/notifications/utils/notification_navigator.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:get/get.dart';

/// Routes a tapped push to the screen it is about.
abstract final class PushTapRouter {
  /// Subscribes both tap paths. Call once, from main(), after runApp() has
  /// been scheduled — navigation needs a live navigator.
  static void wire() {
    // Tapped while the app was backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[push] tap (background) data=${message.data}');
      handleData(message.data);
    });

    // Tapped while the app was killed: the tap launched this process and the
    // message is handed over exactly once, here.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message == null) return; // a normal launch, not a tap
      debugPrint('[push] tap (cold start) data=${message.data}');
      handleData(message.data);
    });
  }

  /// Resolves [data] and navigates. The one body both taps run through.
  ///
  /// A cold-start tap resolves while the app is still on the splash screen,
  /// which finishes by calling `Get.offAllNamed` — anything pushed before
  /// that would be wiped out by it. So the destination is held until the app
  /// has left splash, and is then opened only if the user actually landed on
  /// the signed-in shell: a tap that arrives at the welcome/login screen has
  /// nothing to open, and pushing a chat over a sign-in flow would be worse
  /// than doing nothing.
  static Future<void> handleData(Map<String, dynamic> data) async {
    final destination = destinationFor(data);
    if (!await _waitForShell()) return;
    await openNotificationDestinationFromTray(destination);
  }

  /// Waits for the app to settle on the signed-in shell. False when it does
  /// not get there — still on splash after the timeout, or signed out.
  static Future<bool> _waitForShell() async {
    // 2.4s of splash animation plus restore work; 15s of headroom, polled
    // twice a second, costs nothing and never blocks the UI.
    for (var attempt = 0; attempt < 30; attempt++) {
      final route = Get.currentRoute;
      if (route == AppRoutes.home) return true;
      if (route != AppRoutes.splash && route.isNotEmpty) {
        // Somewhere that is neither splash nor the shell: welcome, login,
        // pending-approval. The notification stays in the list for after
        // sign-in.
        debugPrint('[push] tap not opened: app is on $route');
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('[push] tap not opened: app never reached the shell');
    return false;
  }

  /// Where [data] leads. Exposed so the decision can be asserted directly;
  /// it is [resolveNotificationDestination] with the app's own guest check.
  static NotificationDestination destinationFor(
    Map<String, dynamic> data, {
    bool Function()? isGuest,
  }) {
    return resolveNotificationDestination(data, isGuest: isGuest ?? isGuestMode);
  }
}
