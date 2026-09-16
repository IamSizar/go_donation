// ApiStatusException — a non-2xx answer whose STATUS the caller may need.
//
// WHY THIS FILE EXISTS
// `ModuleApi.getObject` used to throw `Exception('Request failed (404)')` for
// every non-2xx answer, carrying the status only inside a sentence. That is
// fine for a load that either works or does not, and wrong for one where the
// status decides what the user is told. The case that needed it (OPOS #26346):
// a chat group staff deleted or archived answers 404, and a member they
// removed gets 403. Both mean "gone for good", so the conversation screen must
// not offer a Retry that can never succeed.
//
// Parsing the number back out of the message is the pattern this codebase
// rejects — see the header of `history_api.dart` and
// `ModuleApi.openSupportThread` — because it breaks the first time anyone
// rewords the sentence. So the status travels as a field.
//
// It lives in its own file because `module_api.dart` is already past the
// project's 500-line limit.

/// A request the server answered with a non-2xx [statusCode].
///
/// Thrown by `ModuleApi.getObject`. Callers that only care whether a load
/// worked keep catching any exception, exactly as before; a caller whose copy
/// depends on the status checks `is ApiStatusException` and reads
/// [statusCode].
///
/// [toString] reads exactly as the plain `Exception` it replaced, so every
/// `debugPrint` and crash report keeps printing the same line. Like any
/// exception it belongs in the log, never in a widget — see `failureMessage`.
class ApiStatusException implements Exception {
  /// Wraps the HTTP [statusCode] the server answered with.
  const ApiStatusException(this.statusCode);

  /// The HTTP status of the refused request, e.g. 403 or 404.
  final int statusCode;

  @override
  String toString() => 'Exception: Request failed ($statusCode)';
}
