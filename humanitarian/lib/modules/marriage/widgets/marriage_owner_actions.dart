// K14 — the four things a خطوبتي profile's OWNER may do to it: edit, stop
// showing it, show it again, and remove it.
//
// WHY THIS IS A SEPARATE FILE
// marriage_my_profile_screen.dart draws the status card; these are the writes
// that act on it. Keeping them apart holds both files well under the 500-line
// limit, and it keeps the destructive-confirmation flow — the part most worth
// reading carefully — in one place rather than buried in a card's build method.
//
// WHICH ACTIONS ARE OFFERED, AND WHEN
// pause/resume are NOT both shown. The server accepts a pause only from the
// browsable statuses (active / under_review / submitted) and a resume only
// from 'paused', so offering the wrong one would be a control whose whole job
// is to return 409 not_pausable. A profile in any other state (rejected,
// matched, closed) gets neither, with a line saying why — a disabled button
// with no explanation reads as a bug.
//
// THE DELETE IS CONFIRMED, AND THE CONFIRMATION TELLS THE TRUTH
// The server does not delete the row: it stamps owner_deleted_at and closes
// the profile, because marriage_profiles cascades to the mediated chat threads
// and to marriage_subscription_purchases — the record that the user PAID. So
// the dialog says what actually happens (it leaves the browse feed and this
// list; staff can restore it) instead of promising permanent deletion the
// backend deliberately does not perform.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/marriage/controllers/marriage_my_profile_controller.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_profile_edit_screen.dart';

/// The statuses an owner may pause FROM.
///
/// Mirrors `pausableStatuses` in backend/internal/marriage/owner.go — the
/// browsable set, because pausing means "stop showing me" and there is nothing
/// to stop about a profile that is not being shown.
const _pausableStatuses = {'active', 'under_review', 'submitted'};

/// The action row under one profile card.
class MarriageOwnerActions extends StatelessWidget {
  const MarriageOwnerActions({
    super.key,
    required this.controller,
    required this.profile,
  });

  final MarriageMyProfileController controller;

  /// One row of GET /api/marriage/mine.
  final Map<String, dynamic> profile;

  int? get _profileId => profile['id'] is int
      ? profile['id'] as int
      : int.tryParse(profile['id']?.toString() ?? '');

  String get _status => (profile['status'] ?? '').toString().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final id = _profileId;
    // No id means no endpoint to call. Rendering buttons that cannot fire
    // would be the "control that silently does nothing" this codebase keeps
    // finding, so the row is simply absent.
    if (id == null || id <= 0) return const SizedBox.shrink();

    return Obx(() {
      final busy = controller.busyProfileId.value == id;
      final canPause = _pausableStatuses.contains(_status);
      final canResume = _status == 'paused';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionButton(
            key: const Key('marriage_owner_edit'),
            icon: Icons.edit_outlined,
            labelKey: 'marriage_owner_edit',
            busy: false,
            // Editing opens a screen; it does not write from here, so it stays
            // available while another action is in flight.
            onPressed: () => _openEdit(context, id),
          ),
          if (canPause) ...[
            const SizedBox(height: 10),
            _ActionButton(
              key: const Key('marriage_owner_pause'),
              icon: Icons.visibility_off_outlined,
              labelKey: 'marriage_owner_pause',
              busy: busy,
              onPressed: busy ? null : () => _run(controller.pauseProfile(id)),
            ),
          ],
          if (canResume) ...[
            const SizedBox(height: 10),
            _ActionButton(
              key: const Key('marriage_owner_resume'),
              icon: Icons.visibility_outlined,
              labelKey: 'marriage_owner_resume',
              busy: busy,
              onPressed: busy ? null : () => _run(controller.resumeProfile(id)),
            ),
          ],
          // Neither transition is legal here, so the row explains itself
          // rather than showing a button that can only fail.
          if (!canPause && !canResume) ...[
            const SizedBox(height: 10),
            Text(
              'marriage_owner_pause_unavailable'.tr,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _ActionButton(
            key: const Key('marriage_owner_delete'),
            icon: Icons.delete_outline_rounded,
            labelKey: 'marriage_owner_delete',
            busy: busy,
            destructive: true,
            onPressed: busy ? null : () => _confirmAndDelete(context, id),
          ),
        ],
      );
    });
  }

  /// Opens the edit screen. The controller refreshes the list itself on a
  /// successful save, so there is nothing to do on return.
  Future<void> _openEdit(BuildContext context, int id) async {
    AppHaptics.selection();
    await Get.to(
      () => MarriageProfileEditScreen(profileId: id, profile: profile),
    );
  }

  /// Runs a pause/resume and reports only a FAILURE.
  ///
  /// Success is already visible: the card's status tag changes, and the
  /// controller played the success haptic. A "done" snackbar on top of a
  /// screen that visibly updated is noise.
  Future<void> _run(Future<String?> action) async {
    AppHaptics.selection();
    final failure = await action;
    if (failure == null) return;
    Get.snackbar(
      'marriage_my_profile'.tr,
      failure,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(12),
      borderRadius: 12,
    );
  }

  /// Asks before removing, then removes.
  ///
  /// Destructive from the user's point of view even though staff can restore
  /// it, so it is confirmed — and the confirmation describes the real effect
  /// rather than a permanent deletion that does not happen.
  Future<void> _confirmAndDelete(BuildContext context, int id) async {
    AppHaptics.selection();
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: Text('marriage_owner_delete_title'.tr),
        content: Text('marriage_owner_delete_body'.tr),
        actions: [
          // Cancel first and confirm last: on iOS the cancel sits on the left
          // and the destructive choice is marked, which AlertDialog.adaptive
          // renders through CupertinoDialogAction.
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel'.tr),
          ),
          TextButton(
            key: const Key('marriage_owner_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'marriage_owner_delete_confirm'.tr,
              style: TextStyle(color: AppThemeConfig.consequence(context)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final failure = await controller.deleteProfile(id);
    Get.snackbar(
      'marriage_my_profile'.tr,
      // Success says what happened to it, because the card is now gone from
      // the list and a silent disappearance is indistinguishable from a bug.
      failure ?? 'marriage_owner_deleted_ok'.tr,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 5),
      margin: const EdgeInsets.all(12),
      borderRadius: 12,
    );
  }
}

/// One full-width action, with its own in-button progress while it writes.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.labelKey,
    required this.busy,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String labelKey;

  /// True while THIS profile has a write in flight. The button shows a
  /// spinner in place of its icon and refuses a second tap, so one tap cannot
  /// become two requests.
  final bool busy;

  final VoidCallback? onPressed;

  /// Draws the label and border in the consequence tone. Colour is the only
  /// difference — the confirmation dialog is what actually guards the action.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tone = destructive
        ? AppThemeConfig.consequence(context)
        : AppThemeConfig.text(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            )
          : Icon(icon, size: 18, color: tone),
      label: Text(labelKey.tr, style: TextStyle(color: tone)),
    );
  }
}
