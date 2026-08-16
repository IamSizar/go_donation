import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:get/get.dart';

// Note #18 — mirrors BeneficiaryProjectsController (sponsorship module):
// same polling + status-transition-snackbar pattern, applied to the
// current user's OWN marriage profile so they see it move from
// "submitted" to "active"/"rejected"/etc without having to ask staff.
//
// K14 — this controller also owns the four things a profile's OWNER may now do
// to it: edit, pause, resume and remove. They were server-side only until
// commit 9f6ec79; before that the app had no write at all beyond submitting
// another profile, which is why its own menu entry avoided the word "edit".
class MarriageMyProfileController extends GetxController
    with RealtimePollingMixin {
  final profiles = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  /// K14 — the profile id whose owner action is in flight, or null.
  ///
  /// One id rather than a bool: the list can hold several profiles and only
  /// the one being acted on should show a spinner and refuse a second tap.
  final busyProfileId = RxnInt();

  Map<String, String> _lastStatusSnapshot = {};

  @override
  Future<void> realtimePoll() => fetchProfiles(silent: true);

  @override
  void onInit() {
    super.onInit();
    fetchProfiles();
    startPolling();
  }

  /// Loads the caller's own profiles.
  ///
  /// [announce] false refreshes the transition snapshot WITHOUT firing the
  /// "Profile update" alerts. Used by the owner actions below: the user who
  /// just tapped إيقاف does not need an alert telling them their profile was
  /// paused, and an alert shaped like a staff decision would misreport who
  /// made it. The snapshot still moves, so the next poll does not report the
  /// change late.
  Future<void> fetchProfiles({bool silent = false, bool announce = true}) async {
    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final rows = await const ModuleApi().getItems(myMarriageProfileUrl);
      profiles.assignAll(rows);
      _detectAndAnnounceTransitions(announce: announce);
    } catch (_) {
      if (!silent) {
        profiles.clear();
        errorMessage.value = 'marriage_my_profile_load_failed'.tr;
      }
      // Silent polls preserve the previous list on transient errors.
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  // ─── K14 — owner actions ────────────────────────────────────────────────

  /// PATCH the fields the profile card shows.
  ///
  /// [patch] must contain only keys `marriage.OwnerProfilePatch` declares; the
  /// edit screen is the only caller and builds it from that list. Returns null
  /// on success, or a LOCALIZED sentence to show the user.
  Future<String?> updateProfile(int profileId, Map<String, dynamic> patch) {
    return _runOwnerAction(
      profileId,
      () => const ModuleApi().updateMyMarriageProfile(profileId, patch),
    );
  }

  /// Takes the profile out of the browse feed.
  Future<String?> pauseProfile(int profileId) {
    return _runOwnerAction(
      profileId,
      () => const ModuleApi().pauseMyMarriageProfile(profileId),
    );
  }

  /// Puts it back into the status it was paused from.
  Future<String?> resumeProfile(int profileId) {
    return _runOwnerAction(
      profileId,
      () => const ModuleApi().resumeMyMarriageProfile(profileId),
    );
  }

  /// Removes the profile from every surface of the app.
  ///
  /// Recoverable by staff — the row, the mediated chat history and the
  /// subscription purchase record are all kept. Callers must say that rather
  /// than promise permanent deletion.
  Future<String?> deleteProfile(int profileId) {
    return _runOwnerAction(
      profileId,
      () => const ModuleApi().deleteMyMarriageProfile(profileId),
    );
  }

  /// Runs one owner write, refreshes the list from the server, and turns any
  /// failure into a sentence the user can read.
  ///
  /// The refresh is not optional and not an optimistic local edit: pause and
  /// resume both move `status` to a value only the server knows (resume
  /// restores the status the profile was paused FROM), so guessing it here
  /// would print a status the database does not hold.
  Future<String?> _runOwnerAction(
    int profileId,
    Future<Map<String, dynamic>> Function() write,
  ) async {
    if (profileId <= 0) return 'marriage_owner_error_generic'.tr;
    if (busyProfileId.value != null) return null; // one action at a time
    busyProfileId.value = profileId;
    try {
      await write();
      await fetchProfiles(silent: true, announce: false);
      AppHaptics.success();
      return null;
    } on ApiCodedException catch (e) {
      // The server's English sentence goes to the log; the user gets copy
      // written from the machine code. 9f6ec79 is explicit that the English
      // string is a developer fallback and must not reach an Arabic screen.
      debugPrint('marriage owner action on $profileId failed: $e');
      AppHaptics.error();
      return _localizedOwnerError(e.code);
    } catch (e) {
      debugPrint('marriage owner action on $profileId failed: $e');
      AppHaptics.error();
      return 'marriage_owner_error_generic'.tr;
    } finally {
      busyProfileId.value = null;
    }
  }

  /// Maps a server error CODE onto localized copy.
  ///
  /// A `switch` rather than `'marriage_owner_error_$code'.tr`, because GetX
  /// hands back the key when there is no entry: a code added server-side
  /// tomorrow would render the literal string `marriage_owner_error_whatever`
  /// on an Arabic screen. An unknown code falls to the generic sentence, which
  /// is vague but true and in the right language.
  String _localizedOwnerError(String code) {
    return switch (code) {
      'not_owner' => 'marriage_owner_error_not_owner'.tr,
      'not_pausable' => 'marriage_owner_error_not_pausable'.tr,
      'invalid_visibility' => 'marriage_owner_error_invalid_visibility'.tr,
      _ => 'marriage_owner_error_generic'.tr,
    };
  }

  void _detectAndAnnounceTransitions({bool announce = true}) {
    final transitions = detectStatusTransitions<Map<String, dynamic>>(
      items: profiles,
      keyOf: (m) => (m['id'] ?? '').toString(),
      statusOf: (m) => (m['status'] ?? '').toString().toLowerCase(),
      previous: _lastStatusSnapshot,
    );
    _lastStatusSnapshot = {
      for (final m in profiles)
        (m['id'] ?? '').toString(): (m['status'] ?? '')
            .toString()
            .toLowerCase(),
    };
    // The snapshot above is updated either way — skipping it would make the
    // NEXT poll announce a change the user made themselves a moment ago.
    if (!announce) return;
    for (final t in transitions) {
      final msg = _messageForTransition(t.toStatus);
      if (msg == null) continue;
      AppSound.notification();
      AppHaptics.gentle();
      Get.snackbar(
        'marriage_status_update'.tr,
        msg,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    }
  }

  String? _messageForTransition(String to) {
    switch (to) {
      case 'under_review':
        return 'marriage_now_under_review'.tr;
      case 'active':
        return 'marriage_now_active'.tr;
      case 'matched':
        return 'marriage_now_matched'.tr;
      case 'rejected':
        return 'marriage_now_rejected'.tr;
      case 'paused':
        return 'marriage_now_paused'.tr;
      case 'closed':
        return 'marriage_now_closed'.tr;
      default:
        return null;
    }
  }
}
