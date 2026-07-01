# Google OAuth sign-in — setup (Phase 9 · B-09)

The "Continue with Google" flow is **fully wired in code**. To make it work at
runtime you only need to supply real OAuth client IDs and finish the console
setup below — no code changes required.

## 1. Google / Firebase console
In the Firebase project (the one already used for FCM) → **Authentication →
Sign-in method**, enable **Google**. This creates OAuth clients. You need:

- **Web client ID** — used as the *server* client ID (the audience the backend verifies).
- **Android client** — register the app's **SHA-1** (and SHA-256) fingerprints, then
  re-download `google-services.json` into `android/app/`.
- **iOS client** — re-download `GoogleService-Info.plist` into `ios/Runner/`; copy its
  `REVERSED_CLIENT_ID`.

## 2. Backend (Go)
Set the allowed audiences (comma-separated — include the Web client ID and the
platform client IDs whose tokens you accept):

```
GOOGLE_OAUTH_CLIENT_IDS=xxxx-web.apps.googleusercontent.com,yyyy-ios.apps.googleusercontent.com
```

When unset, `POST /api/auth/google` returns **503 "Google sign-in is not
configured"** (wired, awaiting config). Token verification uses Google's
`tokeninfo` endpoint and checks issuer + audience + email_verified.

## 3. Flutter app
Pass the **Web/server client ID** at build time:

```
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx-web.apps.googleusercontent.com
```

(see `lib/api/links.dart` → `googleServerClientId`).

## 4. iOS Info.plist
Replace `com.googleusercontent.apps.REPLACE_WITH_REVERSED_CLIENT_ID` in
`ios/Runner/Info.plist` with the `REVERSED_CLIENT_ID` from
`GoogleService-Info.plist`.

## Behavior
- New Google users are created with **no phone**, `registration_status =
  'incomplete'`, so they still pass through the existing approval flow.
- An existing account with the **same email** gets its `google_sub` linked.
- The response shape matches `/api/auth/login`, so the app treats Google and
  phone/OTP sign-in identically (session persisted, post-login routing shared).
