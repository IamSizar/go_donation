// What a 401 from an AUTHED request means, decided once, in one place.
//
// WHY THIS FILE EXISTS
// Nothing in the app treated "the server does not accept this token" as an
// event at all. `grep -rn "401" lib/` found three sites and none of them were
// about a live session: `history_api.dart` (the identity-code lookup's own
// refusal), `auth_controller.dart` and `controllers/login.dart` — all three
// about a sign-in that was refused, which is a different statement entirely.
// A 401 on an ALREADY SIGNED-IN screen fell through to the generic non-2xx
// branch in `ModuleApi`, which throws `Exception('Request failed (401)')`.
//
// WHAT THAT LOOKED LIKE ON A DEVICE
// The session token was lost and the app kept rendering a fully signed-in UI:
// the dashboard, the tabs, the profile card, all drawn from SharedPreferences
// that nothing had cleared. Every authed screen then showed its designed error
// card with a Retry button — and Retry could never succeed, because retrying a
// request with no valid token produces the same 401 forever. The only way out
// was to know that Logout sits inside the profile menu. That is an
// unrecoverable state reached by doing nothing wrong, and rule 5.7's "a dead-end
// error screen is a bug" names it exactly.
//
// WHAT THIS DOES INSTEAD
// One 401 from an authed request ends the local session the same way the
// Logout button does — [logout] in api/auth_session.dart, reused rather than
// reimplemented, so the token is revoked server-side, the identity prefs are
// wiped and the guest flag is dropped by the code that already knows how — and
// lands the user on the sign-in screen with a sentence saying why.
//
// WHAT IT DELIBERATELY DOES NOT DO
//   • It does not touch the sign-in flows. A wrong password is a legitimate
//     401 and must keep showing its own inline message under the field. Those
//     requests go through `_loginSessionDio` in controllers/login.dart, a
//     private Dio instance that never calls ModuleApi — pinned by
//     test/core/session_expiry_test.dart so a later refactor cannot quietly
//     route sign-in through the choke point and start signing users out for
//     typing their password wrong.
//   • It does not fire more than once. A screen is many requests: the home tab
//     alone runs a dashboard summary, a campaigns load and a 10-second poll, so
//     a dead token produces a burst of 401s within the same frame. Signing out
//     once per 401 would mean a stack of navigations and a stack of snackbars.
//   • It does not fire when there is nothing to end — no stored identity, or a
//     sign-out already in flight, or the user is already sitting on the
//     sign-in screen.
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:get/get.dart';

/// Translation keys for what the user is told. Constants rather than literals
/// because `.tr` returns the key itself when it is missing — silently — so the
/// keys are named once here and pinned by the localization test.
const String kSessionExpiredTitleKey = 'session_expired_title';
const String kSessionExpiredMessageKey = 'session_expired_message';

/// True while a sign-out started by [handleExpiredSession] is still running.
///
/// This is the re-entrancy guard, and it only has to cover the AWAIT inside
/// [handleExpiredSession]: `logout()` posts to /auth/logout with a 5-second
/// timeout, and every other in-flight request can 401 while that is happening.
/// Once the sign-out finishes, `id_user` has been removed — [logout] wipes it
/// along with the rest of the identity — so the identity check below becomes
/// the standing guard and this flag can go back to false without reopening the
/// loop.
bool _signOutInFlight = false;

/// Puts both pieces of process-global state back to their defaults between
/// tests: the re-entrancy guard and the navigation hook.
///
/// A test that left either one set would silently change the next one — a
/// raised guard disarms the handler entirely, and a stale hook would count a
/// later test's sign-out into an earlier test's recorder. Never call this from
/// app code: nothing in the app has a reason to abandon a sign-out half way.
@visibleForTesting
void resetSessionExpiryForTest() {
  _signOutInFlight = false;
  sessionExpiryNavigator = _routeToSignIn;
}

/// Where the user is sent, and how they are told why.
///
/// A function-valued hook rather than a direct call so the decision — "a 401
/// on an authed request ends the session" — can be tested without a navigator,
/// an overlay or a pumped widget tree. The default is [_routeToSignIn]; tests
/// swap it for a recorder and put it back in their tearDown.
@visibleForTesting
Future<void> Function() sessionExpiryNavigator = _routeToSignIn;

/// True when [statusCode] is the server saying "this token is not a session".
///
/// Deliberately 401 ONLY, and not 403. The two are different answers and the
/// app has been burnt by conflating them before: `ModuleApi._authedGet` used to
/// "self-heal" on either, which signed working users out whenever they hit an
/// ordinary permission gate — an approval still pending, a guest restriction.
/// A 403 means "you, correctly identified, may not do this", and the screen's
/// own error state is the right place for it.
bool isSessionExpiredStatus(int statusCode) => statusCode == 401;

/// Ends the local session and routes to sign-in, at most once.
///
/// Returns true only for the call that actually performed the sign-out, so a
/// caller (and a test) can tell "I was the one" from "somebody already did it".
/// Never throws: it is called from inside failure paths that are already about
/// to report a failure to the user, and an exception raised here would replace
/// that report with a worse one.
Future<bool> handleExpiredSession() async {
  if (_signOutInFlight) return false;

  // "The app believes it is signed in" is exactly `id_user`: splash and
  // routeByRegistrationStatus both branch on it, and it is what kept the
  // signed-in UI on screen after the token was gone. It is also removed by
  // [logout], which is what makes this guard self-resetting rather than
  // something that has to be cleared by hand.
  final identity = sharedPreferences.getString('id_user')?.trim() ?? '';
  if (identity.isEmpty) return false;

  // Already on the sign-in screen: there is nothing to route to, and a
  // snackbar over the sign-in form would sit on top of that screen's own
  // error message. Get.currentRoute is '' before any routing has happened,
  // which is not the login route, so this never blocks the first sign-out.
  if (Get.currentRoute == AppRoutes.authLogin) return false;

  _signOutInFlight = true;
  try {
    // Navigate FIRST, then clear. 27.4 — clearing prefs while the
    // authenticated tree is still mounted made every section rebuild against
    // wiped storage and the app went black. `logout()`'s own doc comment says
    // the same thing, and the Logout button in profile.dart is written in this
    // order for this reason.
    await sessionExpiryNavigator();
    await logout();
    return true;
  } catch (e) {
    // NOT a swallow. This runs inside a failure path that is already on its way
    // to reporting something to the user — `ModuleApi` throws its own exception
    // the moment this returns — so an exception raised here would replace that
    // report with a worse one and lose the original failure. `logout()` is
    // already best-effort about the network; what is being caught here is the
    // rest of it (a keystore that refuses a delete, a navigator torn down
    // mid-sign-out). The detail goes to the log, where support can still find
    // it, and the caller's own error still reaches the screen.
    debugPrint('Session expiry sign-out failed: $e');
    return false;
  } finally {
    _signOutInFlight = false;
  }
}

/// The production hook: replace the whole stack with sign-in, then say why.
Future<void> _routeToSignIn() async {
  Get.offAllNamed(AppRoutes.authLogin);
  Get.snackbar(kSessionExpiredTitleKey.tr, kSessionExpiredMessageKey.tr);
}
