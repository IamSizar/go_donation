import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Matches `ios/Runner/GoogleService-Info.plist` and `android/app/google-services.json`.
/// Regenerate with `flutterfire configure` if you change Firebase apps or bundle IDs.
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
    iosBundleId: 'com.easytech.humanitarianApp',
  );
}
