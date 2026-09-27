import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/push_registration.dart';
import 'package:flutter_application_1/core/deep_link_router.dart';
import 'package:flutter_application_1/core/push_tap_router.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/shared/widgets/dismiss_keyboard.dart';
import 'package:flutter_application_1/modules/auth/screens/guest_upgrade.dart';
import 'package:flutter_application_1/modules/auth/screens/login.dart';
import 'package:flutter_application_1/modules/auth/screens/pending_approval.dart';
import 'package:flutter_application_1/modules/auth/screens/registration_form.dart';
import 'package:flutter_application_1/modules/auth/screens/create_password.dart';
import 'package:flutter_application_1/modules/auth/screens/verification.dart';
import 'package:flutter_application_1/modules/auth/screens/welcome.dart';
import 'package:flutter_application_1/modules/dashboard/screens/dashboard_screen.dart';
import 'package:flutter_application_1/modules/notifications/bindings/notifications_binding.dart';
import 'package:flutter_application_1/modules/notifications/screens/notifications_screen.dart';
import 'package:flutter_application_1/modules/splash/screens/splash_screen.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_application_1/firebase_options.dart';

/// Handles pushes that arrive while the app is backgrounded or terminated.
/// Runs in its OWN isolate, so it must initialise Firebase itself — nothing
/// from main()'s isolate is available here. Notification-type messages are
/// still shown by the OS automatically; this handler is what lets data-only
/// messages (and any background bookkeeping) be processed instead of dropped.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  debugPrint(
    '[push] background: ${message.notification?.title} — data=${message.data}',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On Android the Firebase SDK auto-initializes the default app at process
  // start (FirebaseInitProvider, driven by google-services.json). Calling
  // initializeApp() again then throws [core/duplicate-app] — and because the
  // Dart-side Firebase.apps list may not yet reflect that native app, an
  // isEmpty guard isn't reliable. Tolerate the duplicate-app error so main()
  // always reaches runApp() instead of crashing on the native splash; rethrow
  // anything genuinely wrong.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // Register the background/terminated push handler BEFORE any other messaging
  // setup so no early message is missed.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Request the full set of iOS notification permissions explicitly.
  // The default `requestPermission()` call without args still works on
  // Android, but on iOS the user-facing prompt only includes the types
  // you ask for. Without these the system shows a stripped-down prompt
  // and may not grant banner/sound — silently dropping later pushes.
  //
  // On Android 13+ this same call is what requests the POST_NOTIFICATIONS
  // runtime permission (the manifest only declares it). Until the user grants
  // it, Android drops every notification silently — no error anywhere.
  //
  // Wrapped: this runs before runApp(), so an exception here — the plugin
  // raises one when it cannot find the current Activity, and a permission
  // request already in flight is also an error — would abort main() and leave
  // the user staring at the native splash screen. Push setup failing must
  // never cost the app its launch; the permission can be granted later from
  // system settings, and the rest of startup still runs.
  try {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[push] permission status: ${settings.authorizationStatus}');

    // iOS-only: tell the system to display foreground notifications as
    // banner/list/sound. Without this, an incoming push while the app is
    // open is delivered to onMessage but the OS does NOT show any UI —
    // which is what makes admins think "nothing happened".
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
  } catch (e) {
    debugPrint('[push] permission/presentation setup failed: $e');
  }

  // Print the FCM token (NOT the APNs token — they're different strings).
  // Admins paste this into the /push admin form.
  FirebaseMessaging.instance.getToken().then((token) {
    debugPrint('[push] FCM token: $token');
  });

  // Phase 27.3 — wire onTokenRefresh and try to register the token + the
  // user's preferred locale with the backend. Safe to call now: if no
  // session is restored yet, registerNow() no-ops; the login + locale
  // change paths also call it.
  PushRegistration.wire();

  // Foreground messages: log so devs can confirm delivery via console
  // even before the UI work above kicks in.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint(
      '[push] foreground: ${message.notification?.title} — ${message.notification?.body}',
    );
  });

  // Tapping a notification, from the background AND from a killed app.
  //
  // This used to be an onMessageOpenedApp listener that printed a line and
  // navigated nowhere — the client's report: "tapping a notification doesn't
  // open what it's about". PushTapRouter wires both tap paths (the stream
  // here, and getInitialMessage() for the tap that launches the process) to
  // one decision, so a tap lands on the thing the notification is about.
  PushTapRouter.wire();

  // Same idea as PushTapRouter, for a tapped balancenex:// share link
  // instead of a tapped push — see deep_link_router.dart's header.
  DeepLinkRouter.wire();

  await initializeAppState();
  // Loads the persisted access token into memory from the OS-encrypted
  // secure store (migrating any leftover plaintext token from older app
  // versions). Must happen before PushRegistration/UI can read the token.
  await loadApiSessionFromSecureStorage();
  // After state is restored we know whether there's a signed-in user.
  // PushRegistration.registerNow() no-ops when there isn't, so this is
  // safe even on a fresh install / signed-out launch.
  unawaited(PushRegistration.registerNow());
  runApp(const HumanitarianApp());
}

class HumanitarianApp extends StatelessWidget {
  const HumanitarianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, themeMode, _) => GetMaterialApp(
        title: 'Tawazzn',
        debugShowCheckedModeBanner: false,
        // THE BUG THIS FIXES: this used to be a hardcoded `true`, turning on
        // GetX's edge-swipe-to-pop gesture on Android too (GetX defaults it
        // to iOS-only). Reported live: back out of a pushed screen (e.g.
        // Events → a profile) with Android's OWN back gesture — a touch
        // starting right at the screen edge, exactly where this recognizer
        // also lives — and the WHOLE APP stops responding to any touch,
        // needing a restart. Captured with adb logcat at the moment it
        // happens: a system `BackPanelController` window (Android's native
        // predictive-back edge panel) appears, the pop completes, and then
        // not even a raw `PointerDownEvent` reaches Flutter's own root
        // Listener again — not a widget swallowing the event, the SURFACE
        // stops receiving input. Two separate "edge drag = go back"
        // recognizers — Android's own gesture-nav panel and this one —
        // owning the same screen edge at once. Android already has its own
        // back gesture; it does not also need Flutter's. iOS has no
        // equivalent system gesture GetX can hook into, which is why GetX's
        // own default restricts this to iOS in the first place — this line
        // now just stops overriding that default instead of fighting it.
        popGesture: GetPlatform.isIOS,
        // THE BUG THIS FIXES: every `Get.to()` call in this app that doesn't
        // name its own `transition:` — the large majority of them — fell
        // through to GetX's own default, `Transition.cupertino`. That
        // transition keeps BOTH the outgoing and incoming screen's widget
        // trees mounted and animating together (an iOS-style slide-over),
        // so for the ~200ms the animation runs, the screen being popped is
        // still on screen sliding away — including its own back arrow.
        // Reported live: backing out of Events shows a stray back button
        // top-left for "half a second" before it disappears — that stray
        // button is the outgoing screen's real header, still mid-exit. A
        // plain fade has no second screen's chrome to leak through: the
        // outgoing screen fades out in place while the incoming one fades
        // in, never both fully opaque and slid apart at once. Explicit
        // `transition:`s already set on individual GetPages (splash,
        // welcome, the auth flow) are unaffected — this only fills in the
        // fallback for routes that never specified one.
        defaultTransition: Transition.fadeIn,
        transitionDuration: const Duration(milliseconds: 220),
        translations: AppTranslations(),
        locale: appLocale,
        fallbackLocale: AppLocaleService.english,
        supportedLocales: AppLocaleService.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppThemeConfig.buildTheme(Brightness.light),
        darkTheme: AppThemeConfig.buildTheme(Brightness.dark),
        themeMode: themeMode,
        builder: (context, child) {
          final locale =
              Get.locale ?? Localizations.maybeLocaleOf(context) ?? appLocale;
          final themed = AppThemeConfig.applyLocaleFont(
            Theme.of(context),
            locale,
          );
          // Global keyboard dismiss: a tap on any empty area anywhere in the
          // app unfocuses the active field and closes the keyboard.
          return Theme(
            data: themed,
            child: MediaQuery(
              // Clamp the system font-scale setting so a large accessibility
              // text size on the device can't blow up headings/cards past
              // what the layouts were designed for.
              data: MediaQuery.of(context).copyWith(
                textScaler: MediaQuery.of(
                  context,
                ).textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15),
              ),
              child: DismissKeyboardOnTap(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
        initialRoute: AppRoutes.splash,
        getPages: [
          GetPage(name: AppRoutes.splash, page: () => const SplashScreen()),
          GetPage(
            name: AppRoutes.welcome,
            page: () => const WelcomeScreen(),
            transition: Transition.fadeIn,
            transitionDuration: const Duration(milliseconds: 320),
          ),
          GetPage(name: AppRoutes.authLogin, page: () => const LoginPage()),
          // THE BUG THIS FIXES: left without an explicit `transition`, these
          // two fell back to GetX's own default — `Transition.cupertino`,
          // which (unlike every other route here that bothered to pin one)
          // keeps an edge-swipe-to-pop gesture recognizer live for the whole
          // transition. A tap landing on the incoming page's first
          // interactive control — reported here as tapping the new
          // password field the instant "Choose a password" appeared — could
          // land while that recognizer was still in the gesture arena
          // deciding whether the touch was a tap or the start of a
          // swipe-back, and lose the ambiguity: the route popped back to
          // the OTP screen instead of focusing the field. Intermittent by
          // nature (a timing race against the transition's own animation),
          // which matches it working after a few retries once the
          // transition had settled before the tap landed. `fadeIn` has no
          // gesture recognizer of its own to race against.
          GetPage(
            name: AppRoutes.authVerify,
            page: () => const VerificationPage(),
            transition: Transition.fadeIn,
            transitionDuration: const Duration(milliseconds: 220),
          ),
          GetPage(
            name: AppRoutes.authCreatePassword,
            page: () => const CreatePasswordPage(),
            transition: Transition.fadeIn,
            transitionDuration: const Duration(milliseconds: 220),
          ),
          GetPage(
            name: AppRoutes.registration,
            page: () => const RegistrationFormPage(),
            transition: Transition.fadeIn,
            transitionDuration: const Duration(milliseconds: 320),
          ),
          GetPage(
            name: AppRoutes.pendingApproval,
            page: () => const PendingApprovalPage(),
            transition: Transition.fadeIn,
            transitionDuration: const Duration(milliseconds: 320),
          ),
          GetPage(name: AppRoutes.home, page: () => const DashboardScreen()),
          GetPage(
            name: AppRoutes.guestUpgrade,
            page: () => const GuestUpgradeScreen(),
          ),
          GetPage(
            name: AppRoutes.notifications,
            page: () => const NotificationsScreen(),
            binding: NotificationsBinding(),
          ),
        ],
      ),
    );
  }
}
