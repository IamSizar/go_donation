import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/push_registration.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/auth/screens/login.dart';
import 'package:flutter_application_1/modules/auth/screens/pending_approval.dart';
import 'package:flutter_application_1/modules/auth/screens/register.dart';
import 'package:flutter_application_1/modules/auth/screens/registration_form.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Request the full set of iOS notification permissions explicitly.
  // The default `requestPermission()` call without args still works on
  // Android, but on iOS the user-facing prompt only includes the types
  // you ask for. Without these the system shows a stripped-down prompt
  // and may not grant banner/sound — silently dropping later pushes.
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
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

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
    debugPrint('[push] foreground: ${message.notification?.title} — ${message.notification?.body}');
  });

  // Tapping a notification when the app is in the background or terminated.
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('[push] opened from notification: ${message.notification?.title}');
  });

  await initializeAppState();
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
        title: 'Humanitarian Platform',
        debugShowCheckedModeBanner: false,
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
          return Theme(data: themed, child: child ?? const SizedBox.shrink());
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
          GetPage(
            name: AppRoutes.authRegister,
            page: () => const RegisterPage(),
          ),
          GetPage(
            name: AppRoutes.authVerify,
            page: () => const VerificationPage(),
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
            name: AppRoutes.notifications,
            page: () => const NotificationsScreen(),
            binding: NotificationsBinding(),
          ),
        ],
      ),
    );
  }
}
