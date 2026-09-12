// OPOS #25280 — "adding a City Guide activity shows 'failed to send', but it
// appears in the list anyway."
//
// ROOT CAUSE: ModuleApi's 12-second request timeout does not cancel the
// underlying HTTP call (Dart's Future.timeout only stops AWAITING it), so a
// slow-but-alive server can still insert the row after the app has already
// given up and shown failure. The screen's catch block used to show the same
// flat "activity_submit_failed" message for every exception, which is a
// categorical lie for that case: the request may well have succeeded.
//
// THE FIX pins the SAME distinction isOfflineFailure already draws elsewhere
// in this codebase (see failure_message_test.dart) onto a dedicated pure
// function, so it can be pinned directly with synthetic exceptions -- no
// widget pump, no real timer, exactly like isOfflineFailure's own tests.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_application_1/modules/community/screens/add_activity_screen.dart';

void main() {
  group('activitySubmitFailureKey', () {
    test('a timeout is NOT reported as a definite failure', () {
      // The exact exception type ModuleApi's 12s timeout raises.
      expect(
        activitySubmitFailureKey(TimeoutException('timed out')),
        'activity_submit_unconfirmed',
        reason:
            'a timeout does not mean the server never got the request -- it '
            'may have inserted the row anyway',
      );
    });

    test('a dropped/unreachable connection is NOT reported as a definite failure', () {
      expect(
        activitySubmitFailureKey(const SocketException('Network is unreachable')),
        'activity_submit_unconfirmed',
      );
      expect(
        activitySubmitFailureKey(const HandshakeException('bad cert')),
        'activity_submit_unconfirmed',
      );
      expect(
        activitySubmitFailureKey(http.ClientException('Connection closed')),
        'activity_submit_unconfirmed',
      );
    });

    test('a genuine server rejection IS reported as a definite failure', () {
      // What postJson throws for a non-2xx response or success != true --
      // the request definitely reached the server and it definitely said no.
      expect(
        activitySubmitFailureKey(Exception('category is required.')),
        'activity_submit_failed',
      );
    });
  });
}
