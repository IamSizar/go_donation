// Looking a donation / support history up by identity code (K21).
//
// WHY THIS FILE EXISTS AND IS NOT A METHOD ON ModuleApi
// `ModuleApi.getObject` collapses every non-2xx answer into
// `Exception('Request failed (404)')`, which is the right shape for a load that
// either works or does not — and the wrong shape here. This endpoint has THREE
// meaningful failures the app must tell apart and say different things about:
//
//   404  the code names nobody, OR it names somebody else. The server answers
//        these IDENTICALLY on purpose (history_code.go): the codes are
//        sequential, so confirming one code is real confirms the range. The app
//        must not undo that by guessing which of the two happened.
//   403  a staff caller without the (users, view) permission.
//   else a fault or an unreachable network — ours, not the user's.
//
// So this reads the status itself and returns an OUTCOME rather than throwing a
// string a screen would end up printing. `ModuleApi` is already past this
// project's file-size limit, and splitting it is a separate job, so the new
// endpoint gets its own file next to the other `*_api.dart` readers.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:http/http.dart' as http;

/// Matches ModuleApi's own timeout: a request that never returns also never
/// runs its caller's `finally`, which is how a screen gets stuck loading.
const Duration _lookupTimeout = Duration(seconds: 12);

/// What the server said about an identity-code lookup.
enum HistoryLookupOutcome {
  /// The timeline is in [HistoryLookup.data].
  ok,

  /// No history is available for that code. Covers BOTH "no such code" and
  /// "that is someone else's" — see the file header for why they are one case.
  notFound,

  /// A staff caller who may not read other people's records.
  notPermitted,

  /// A fault, a bad body, or no network. Ours to apologise for.
  failed,
}

/// The result of one lookup, with the message the screen should show.
class HistoryLookup {
  const HistoryLookup(this.outcome, {this.data});

  final HistoryLookupOutcome outcome;

  /// The `GET /api/history` body, present only when [outcome] is
  /// [HistoryLookupOutcome.ok].
  final Map<String, dynamic>? data;

  /// The translation key for what to tell the user, or null on success.
  ///
  /// A KEY rather than the server's English sentence: the app renders this in
  /// four languages, and the server sends one. The wordings deliberately mirror
  /// what the server says so support reading a log and a user reading a screen
  /// are looking at the same claim.
  String? get messageKey => switch (outcome) {
    HistoryLookupOutcome.ok => null,
    HistoryLookupOutcome.notFound => 'history_code_not_found',
    HistoryLookupOutcome.notPermitted => 'history_code_not_permitted',
    HistoryLookupOutcome.failed => 'history_code_failed',
  };
}

/// Fetches the timeline belonging to [code].
///
/// [code] is sent as the user typed it, only trimmed. The server matches
/// case-insensitively on the trimmed value on purpose — a code is copied off a
/// receipt and typed back by hand — so normalising it here would be a second,
/// silently different rule.
///
/// Never throws: every failure is an outcome, because the caller's job is to
/// render a message rather than to catch a string.
Future<HistoryLookup> fetchHistoryByCode(String code) async {
  final trimmed = code.trim();
  if (trimmed.isEmpty) {
    // Nothing to ask. Reported as "no history for that code" rather than as a
    // fault, because an empty box is not a server problem.
    return const HistoryLookup(HistoryLookupOutcome.notFound);
  }

  final uri = Uri.parse(
    roleHistoryUrl,
  ).replace(queryParameters: withApiAuthQueryParameters({'code': trimmed}));

  try {
    final response = await http
        .get(uri, headers: withApiAuthHeaders())
        .timeout(_lookupTimeout);

    switch (response.statusCode) {
      case 200:
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
          // A 200 that does not say success is a shape we do not understand,
          // which is our problem and not a statement about the code.
          return const HistoryLookup(HistoryLookupOutcome.failed);
        }
        return HistoryLookup(HistoryLookupOutcome.ok, data: decoded);
      case 403:
        return const HistoryLookup(HistoryLookupOutcome.notPermitted);
      case 404:
        return const HistoryLookup(HistoryLookupOutcome.notFound);
      case 401:
        // An expired session. Reported as a failure rather than as "no such
        // code", which would be a lie about the code.
        return const HistoryLookup(HistoryLookupOutcome.failed);
      default:
        return const HistoryLookup(HistoryLookupOutcome.failed);
    }
  } catch (e) {
    // NOT a swallow: `failed` is this function's failure signal and the caller
    // renders it. The code itself is never logged — it identifies a person.
    debugPrint('fetchHistoryByCode: lookup failed: $e');
    return const HistoryLookup(HistoryLookupOutcome.failed);
  }
}
