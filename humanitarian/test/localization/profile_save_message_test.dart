// E17 — the profile screen must not claim a change was saved when the server
// queued it for staff review.
//
// THE SHAPE OF THE BUG
// `POST /api/profile/set` has returned a `pending_review` list since migration
// 093, and the handler's own comment says why: "So the app can say 'waiting
// for approval' instead of appearing to have silently ignored the edit."
// Nothing in the app read the key. `edit_profile.dart` ran one unconditional
// snackbar — "Your profile details have been saved." — so a user who changed
// their name was told it had landed, went back to their profile, and saw the
// OLD name with no explanation.
//
// It is the worst kind of wrong message: the request succeeded, nothing
// errored, and the app confidently described something that had not happened.
//
// WHAT IS ASSERTED
// The decision, not the snackbar. `profileSaveMessage` is a pure function over
// the API result precisely so this can be checked without pumping a screen or
// mocking a multipart upload — and so the four outcomes are visible in one
// place instead of buried in a widget.
//
// Plus the property the whole of group B is about: whatever the outcome, the
// Arabic the user actually reads must contain no English.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/localization/app_translations.dart';

/// A successful save that queued [pending] for review.
ProfileUpdateResult resultWithPending(List<String> pending) =>
    ProfileUpdateResult.success(
      fullName: 'Sizar Ahmed',
      address: 'Erbil',
      gender: 'male',
      pendingReview: pending,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('profileSaveMessage tells the truth about what happened', () {
    test('nothing queued — the old "saved" message is correct and kept', () {
      final message = profileSaveMessage(resultWithPending(const []));
      expect(message.title, 'Profile updated');
      expect(message.body, 'Your profile details have been saved.');
    });

    test('a missing pending_review key is treated as nothing queued', () {
      // An older server build does not send the field at all. That must read
      // as "everything applied", not as a crash and not as a review claim.
      const result = ProfileUpdateResult.success(
        fullName: 'Sizar Ahmed',
        address: 'Erbil',
        gender: 'male',
      );
      expect(result.pendingReview, isEmpty);
      expect(profileSaveMessage(result).title, 'Profile updated');
    });

    test('name queued — the message says so and does not claim it is saved', () {
      final message = profileSaveMessage(resultWithPending([fieldFullName]));
      expect(message.title, 'Saved — waiting for approval');
      expect(message.body, contains('name'));
      // The exact regression: the old sentence must not be what is shown.
      expect(message.body, isNot('Your profile details have been saved.'));
    });

    test('photo queued — names the photo, not the name', () {
      final message =
          profileSaveMessage(resultWithPending([fieldProfilePicture]));
      expect(message.title, 'Saved — waiting for approval');
      expect(message.body, contains('photo'));
      expect(message.body, isNot(contains('name')));
    });

    test('both queued — one message covering both, not two snackbars', () {
      final message = profileSaveMessage(
        resultWithPending([fieldFullName, fieldProfilePicture]),
      );
      expect(message.title, 'Saved — waiting for approval');
      expect(message.body, contains('name'));
      expect(message.body, contains('photo'));
    });

    test('every outcome still mentions that the other details ARE saved', () {
      // Address and gender apply immediately (profile.go). A message that only
      // mentioned the review would be misleading in the opposite direction —
      // the user would think nothing at all had been saved.
      for (final pending in [
        [fieldFullName],
        [fieldProfilePicture],
        [fieldFullName, fieldProfilePicture],
      ]) {
        expect(
          profileSaveMessage(resultWithPending(pending)).body,
          contains('other details are saved'),
          reason: 'pending: $pending',
        );
      }
    });

    test('the queued flags read the server field names, not app-local ones', () {
      // These two strings are the Go constants profilechanges.FieldFullName and
      // FieldPicture. If the backend renames one, this test is where it shows.
      expect(fieldFullName, 'full_name');
      expect(fieldProfilePicture, 'profile_picture');
      final result = resultWithPending(['full_name']);
      expect(result.isNamePending, isTrue);
      expect(result.isPicturePending, isFalse);
    });
  });

  group('the Arabic a user reads is Arabic', () {
    setUp(() {
      Get.locale = const Locale('ar', 'SA');
      Get.addTranslations(AppTranslations().keys);
    });
    tearDown(() => Get.locale = null);

    test('every profile-save message resolves with no Latin letters left', () {
      for (final pending in [
        <String>[],
        [fieldFullName],
        [fieldProfilePicture],
        [fieldFullName, fieldProfilePicture],
      ]) {
        final message = profileSaveMessage(resultWithPending(pending));
        for (final line in [message.title.tr, message.body.tr]) {
          expect(
            RegExp(r'[A-Za-z]').hasMatch(line),
            isFalse,
            reason:
                'pending: $pending rendered "$line" — either the key has no '
                'Arabic entry (GetX returns the key) or the Arabic is English.',
          );
        }
      }
    });
  });
}
