// Turns a caught exception into a sentence a user can act on.
//
// WHY THIS FILE EXISTS
// Seventeen `catch` blocks across the app ended in
// `Get.snackbar('Error'.tr, e.toString())`. That is forbidden by the project's
// own standard — "Errors are designed, not dumped. Raw exceptions, status
// codes, or stack traces must never reach the user" — and the codebase already
// records it as a defect in `proposal_services_section.dart`, where the
// same line was deleted along with the screen carrying it. It was fixed in
// that one place and left in the rest.
//
// What reached an Arabic screen was English prose, Latin digits, and on the
// volunteer check-in path a literal Postgres message: the backend's
// `volunteer_checkin.go` answers a failed insert with
// `"Database error: " + err.Error()`.
//
// WHAT THIS DOES AND DELIBERATELY DOES NOT DO
// A user-facing error must say what happened and what to do next. Only the
// second half can be decided centrally, so that is all this file decides:
// each call site names WHAT failed with its own key, and [failureMessage]
// appends the recovery clause chosen from the exception's TYPE.
//
// It does NOT try to distinguish "you sent something invalid" from "the server
// broke". `ModuleApi.postJson` throws a bare `Exception` carrying only the
// server's English sentence — no machine code and no status — so any such
// split would be guesswork, and both cases lead the user to the same action
// anyway. Where the server DOES name a failure (the K14 owner routes) the app
// already localizes from the code: see `ApiCodedException` and
// `marriage_my_profile_controller._localizedOwnerError`. That mechanism is the
// one to extend when more endpoints start naming their failures — not this
// one, which is the fallback for endpoints that name nothing.
//
// The technical detail is not discarded; every call site `debugPrint`s the
// exception so support can trace what the user saw.
import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// True when [error] means the request never reached a working server.
///
/// The distinction is the whole point of this file: "check your connection" is
/// useful advice when the phone is offline and an outright lie when the server
/// answered with a refusal. Only the transport-level exceptions can be
/// recognised without inventing meaning — [SocketException] (no route, refused,
/// DNS), [HandshakeException] (TLS, a subtype of IOException), `http`'s own
/// [http.ClientException], and the [TimeoutException] raised by ModuleApi's
/// 12-second `_requestTimeout`.
///
/// Everything else — including the plain `Exception(serverSentence)` that
/// `postJson` throws for any non-2xx — is treated as "the server said no".
bool isOfflineFailure(Object error) {
  return error is SocketException ||
      error is HandshakeException ||
      error is http.ClientException ||
      error is TimeoutException;
}

/// "What failed, then what to do next" — localized, for a failure the user
/// must be told about.
///
/// [whatFailedKey] is a translation key naming the operation in the user's
/// words — "Could not record your check-in." It is a KEY and not a sentence
/// because GetX's `.tr` returns the key unchanged when it is missing, silently;
/// every key passed here is pinned by `test/localization/failure_message_test`
/// so a typo fails a test instead of printing `error_checkin_failed` on screen.
///
/// The caller is still responsible for logging [error] — this function never
/// renders it.
String failureMessage(Object error, String whatFailedKey) =>
    failureMessageFor(offline: isOfflineFailure(error), whatFailedKey: whatFailedKey);

/// [failureMessage] for a call site that no longer holds the exception.
///
/// Some failures cross a boundary that keeps the outcome and drops the error —
/// [SupportChatFailed] is one, carrying the detail as a string and the
/// offline-ness as a bool decided where the exception still existed. Such a
/// caller must compose the same sentence from the same two keys, and doing it
/// by hand is how the two halves drift apart.
String failureMessageFor({
  required bool offline,
  required String whatFailedKey,
}) {
  final whatFailed = whatFailedKey.tr;
  final whatToDoNext = offline ? 'error_next_offline'.tr : 'error_next_retry'.tr;
  return '$whatFailed $whatToDoNext';
}
