// The eighteen `Get.snackbar('Error', e.toString())` sites, reduced to one
// decision that can be asserted without pumping a screen.
//
// THE SHAPE OF THE BUG
// Every write in the app caught its failure and printed the exception:
//
//     } catch (e) { Get.snackbar('Error'.tr, e.toString()); }
//
// so an Arabic-speaking volunteer tapping "check in" against a broken database
// read `Exception: Database error: pq: duplicate key value violates unique
// constraint "volunteer_mission_signups_pkey"` — English, Latin digits, a
// Postgres constraint name, and no hint of what to do next. The codebase
// already names this a defect in `proposal_services_section.dart`, where
// the same pattern was deleted along with the screen that carried it.
//
// WHAT IS ASSERTED HERE
// The decision, not the snackbar: [isOfflineFailure] and [failureMessage] are
// pure functions precisely so the "what do I tell the user to do" branch is
// checkable in one place. The screens then only have to name WHAT failed.
//
// Plus the property group B is about: the Arabic a user reads carries no
// English, whichever branch produced it.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/failure_message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'isOfflineFailure separates "the network" from "the server said no"',
    () {
      test('a dropped socket is a connectivity failure', () {
        expect(
          isOfflineFailure(const SocketException('no route to host')),
          isTrue,
        );
      });

      test('the 12s request timeout is a connectivity failure', () {
        expect(isOfflineFailure(TimeoutException('timed out')), isTrue);
      });

      test('an http client failure (DNS, refused, TLS) is connectivity', () {
        expect(
          isOfflineFailure(http.ClientException('Connection closed')),
          isTrue,
        );
        expect(isOfflineFailure(const HandshakeException('bad cert')), isTrue);
      });

      // The one that matters: ModuleApi.postJson throws a plain Exception
      // carrying the SERVER's English sentence. That is a refusal, not an
      // outage, and telling the user to check their connection would be a lie.
      test(
        'a server refusal carried as a bare Exception is NOT connectivity',
        () {
          expect(
            isOfflineFailure(
              Exception('This signup is not awaiting check-in.'),
            ),
            isFalse,
          );
        },
      );
    },
  );

  group('failureMessage says what failed and what to do next', () {
    setUp(() {
      Get.clearTranslations();
      Get.addTranslations(AppTranslations().keys);
      Get.locale = const Locale('en', 'US');
    });

    tearDown(() => Get.locale = const Locale('en', 'US'));

    test('offline failures advise the connection, not support', () {
      final message = failureMessage(
        const SocketException('down'),
        'error_checkin_failed',
      );
      expect(message, contains('Could not record your check-in.'));
      expect(message, contains('Check your connection'));
    });

    test('a server refusal advises retry, and never quotes the server', () {
      final message = failureMessage(
        Exception('pq: duplicate key value violates unique constraint'),
        'error_checkin_failed',
      );
      expect(message, contains('Could not record your check-in.'));
      expect(message, isNot(contains('pq:')));
      expect(message, isNot(contains('Exception')));
    });

    // An unknown key would render the literal key name — GetX returns the key
    // unchanged when it is missing, silently, which is this codebase's most
    // common bug. Every key this helper is called with is pinned below.
    test(
      'every whatFailed key used by the app resolves in English and Arabic',
      () {
        const keysInUse = <String>[
          'error_role_change_failed',
          'error_gps_capture_failed',
          'error_privacy_settings_save_failed',
          'error_service_request_failed',
          'error_subscription_failed',
          'error_photo_upload_failed',
          'error_attachment_upload_failed',
          'error_order_checkout_failed',
          'error_case_submit_failed',
          'error_sponsorship_submit_failed',
          'error_in_kind_submit_failed',
          'error_evidence_capture_failed',
          'error_checkin_failed',
          'error_mission_checkout_failed',
          'error_join_mission_failed',
          'error_volunteer_application_failed',
          'error_next_offline',
          'error_next_retry',
        ];
        for (final key in keysInUse) {
          expect(
            AppTranslations.englishForTest.containsKey(key),
            isTrue,
            reason:
                '$key is missing from _en, so .tr would render the key name',
          );
          expect(
            AppTranslations.arabicForTest.containsKey(key),
            isTrue,
            reason:
                '$key is missing from _ar, so an Arabic screen shows English',
          );
        }
      },
    );

    test('the Arabic a user reads contains no Latin letters', () {
      Get.locale = const Locale('ar', 'SA');
      final offline = failureMessage(
        const SocketException('down'),
        'error_join_mission_failed',
      );
      final refused = failureMessage(
        Exception('Database error: pq: relation does not exist'),
        'error_join_mission_failed',
      );
      expect(RegExp(r'[A-Za-z]').hasMatch(offline), isFalse, reason: offline);
      expect(RegExp(r'[A-Za-z]').hasMatch(refused), isFalse, reason: refused);
    });
  });
}
