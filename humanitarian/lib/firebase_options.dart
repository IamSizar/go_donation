import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Matches `ios/Runner/GoogleService-Info.plist` and `android/app/google-services.json`.
/// Regenerate with `flutterfire configure` if you change Firebase apps or bundle IDs.
///
/// PENDING (2026-09-27): the app was renamed to `com.tawazzn` on both
/// platforms (client directive — unify the project identity to @tawazzn
/// everywhere). [ios]'s `iosBundleId` below is updated to match, but every
/// other value here — `apiKey`, `appId`, `projectId` — plus both
/// `GoogleService-Info.plist` and `google-services.json` still point at the
/// OLD Firebase app registrations (`com.easytech.humanitarianApp` /
/// `com.easytech.humanitarian`). Firebase has no "rename a registered app"
/// operation: someone with access to the Firebase console has to add
/// `com.tawazzn` as a NEW app under each platform, download its config files,
/// and this file gets regenerated from them with `flutterfire configure`.
/// Until then, push notifications and anything else touching Firebase will
/// not work correctly under the new ID — this is expected, not a bug to chase.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions are not configured for web.',
      );
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => throw UnsupportedError(
        'DefaultFirebaseOptions are not supported for this platform.',
      ),
    };
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyASXDUrFFAQJFESzv3GLpUS2WPCV-lKsdE',
    appId: '1:463997425388:android:073d1ca87ff7c9ae',
    messagingSenderId: '463997425388',
    projectId: 'human-f1dc6',
    storageBucket: 'human-f1dc6.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyASXDUrFFAQJFESzv3GLpUS2WPCV-lKsdE',
    appId: '1:463997425388:ios:ae711aaa073d1ca87ff7c9',
    messagingSenderId: '463997425388',
    projectId: 'human-f1dc6',
    storageBucket: 'human-f1dc6.firebasestorage.app',
    iosBundleId: 'com.tawazzn',
  );
}
