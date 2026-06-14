import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/support/widgets/availability_schedule_picker.dart';
import 'package:flutter_application_1/modules/support/widgets/skill_chip_picker.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class SupportSection extends StatefulWidget {
  const SupportSection({super.key});

  @override
  State<SupportSection> createState() => _SupportSectionState();
}

class _SupportSectionState extends State<SupportSection>
    with WidgetsBindingObserver {
  late Future<Map<String, dynamic>> _future;
  bool _isRefreshing = false;

  // Phase 25 — real-time polling so admin actions (approve / mark attended /
  // mark completed / etc.) surface to the volunteer within ~5 seconds
  // without manual refresh. Paused when app is backgrounded to save
  // battery + bandwidth.
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 5);

  // Snapshot of the volunteer's current signup statuses (keyed by signup id).
  // Compared on each poll to detect transitions (e.g. pending → approved)
  // and pop a snackbar so the volunteer feels the update happen live.
  Map<int, String> _lastSignupStatus = {};

  int get _userId =>
      int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Observe lifecycle so we can pause/resume polling on
    // backgrounding — Flutter's WidgetsBinding is the simplest way.
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        // Refresh once immediately on return, then resume polling.
        _silentRefresh();
        _startPolling();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _pollTimer?.cancel();
        _pollTimer = null;
        break;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _silentRefresh());
  }

  /// Same as _refresh but without setting _isRefreshing (no spinner) and
  /// runs a status-diff to detect admin actions while the volunteer was
  /// looking. Skips when a manual refresh is already in flight to avoid
  /// double-fetching the same data.
  Future<void> _silentRefresh() async {
    if (!mounted || _isRefreshing || _userId <= 0) return;
    try {
      final result = await ModuleApi().volunteerDashboard(_userId).timeout(
            const Duration(seconds: 8),
          );
      if (!mounted) return;
      _detectStatusChanges(result);
      setState(() => _future = Future.value(result));
    } catch (_) {
      // Silent fail — the UI keeps the last good snapshot. The next tick
      // will retry. A persistent network outage just means the volunteer
      // sees slightly-stale data, not a crash.
    }
  }

  /// Compare the new joined_missions snapshot against _lastSignupStatus,
  /// pop a snackbar (+ gentle haptic) for any signup whose status changed.
  /// Snackbar copy reads naturally per transition.
  void _detectStatusChanges(Map<String, dynamic> result) {
    final joined = (result['joined_missions'] as List?) ?? const [];
    final next = <int, String>{};
    for (final raw in joined) {
      if (raw is! Map) continue;
      final id = int.tryParse((raw['signup_id'] ?? '').toString());
      final status = (raw['signup_status'] ?? '').toString();
      if (id == null || status.isEmpty) continue;
      next[id] = status;

      final prev = _lastSignupStatus[id];
      if (prev != null && prev != status) {
        final missionTitle = (raw['title'] ?? '').toString();
        final message = _messageForTransition(prev, status, missionTitle);
        if (message != null) {
          AppSound.notification();
          AppHaptics.gentle();
          // Get.snackbar is non-blocking and auto-dismisses.
          Get.snackbar(
            'Mission update'.tr,
            message,
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 5),
            margin: const EdgeInsets.all(12),
            borderRadius: 12,
          );
        }
      }
    }
    _lastSignupStatus = next;
  }

  /// Returns the user-facing snackbar copy for a status transition, or
  /// null when the transition is a no-op (admin re-saved the same state).
  String? _messageForTransition(String from, String to, String missionTitle) {
    final m = missionTitle.isEmpty ? 'your mission'.tr : '"$missionTitle"';
    switch (to) {
      case 'approved':
        return 'Your join request for @m was approved!'.trParams({'m': m});
      case 'rejected':
        return 'Your join request for @m was rejected.'.trParams({'m': m});
      case 'cancelled':
        return 'Your join request for @m was cancelled.'.trParams({'m': m});
      case 'joined':
        return 'Your attendance for @m was recorded.'.trParams({'m': m});
      case 'completion_requested':
        return 'Your completion is under review for @m.'.trParams({'m': m});
      case 'completed':
        return 'Mission @m marked complete. Thank you!'.trParams({'m': m});
      case 'no_show':
        return 'You were marked absent for @m.'.trParams({'m': m});
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> _load() async {
    if (_userId <= 0) {
      return {
        'success': true,
        'items': <Map<String, dynamic>>[],
        'applications': <Map<String, dynamic>>[],
        'joined_missions': <Map<String, dynamic>>[],
      };
    }
    try {
      return await const ModuleApi()
          .volunteerDashboard(_userId)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'items': <Map<String, dynamic>>[],
        'applications': <Map<String, dynamic>>[],
        'joined_missions': <Map<String, dynamic>>[],
      };
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    final next = _load();
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _future = next;
      });
    }
    await next;
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Volunteer',
      subtitle:
          'Join missions, manage shifts, and follow local field activities.',
      trailing: IconButton.filledTonal(
        onPressed: _isRefreshing ? null : _refresh,
        icon: _isRefreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded),
        tooltip: 'Refresh'.tr,
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data ?? const <String, dynamic>{};
          final loadError = data['success'] == false
              ? (data['error'] ?? 'Unable to load volunteer missions.')
                    .toString()
              : '';
          final missions = _listFrom(data['items']);
          final applications = _listFrom(data['applications']);
          final joinedMissions = _listFrom(data['joined_missions']);
          final latestApplication = applications.isEmpty
              ? null
              : applications.first;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            children: [
              SectionTile(
                icon: Icons.person_add_alt_1_rounded,
                title: latestApplication == null
                    ? 'Volunteer application'
                    : 'My volunteer application',
                subtitle: latestApplication == null
                    ? 'Submit your skills and availability to the institution.'
                    : _applicationSubtitle(latestApplication),
                color: _applicationColor(
                  (latestApplication?['status'] ?? '').toString(),
                ),
                onTap: () async {
                  final changed = await Get.to<bool>(
                    () => const VolunteerApplicationFormScreen(),
                  );
                  if (changed == true && mounted) {
                    await _refresh();
                  }
                },
              ),
              const SizedBox(height: 12),
              if (joinedMissions.isNotEmpty) ...[
                const SectionLabel(title: 'My missions'),
                const SizedBox(height: 12),
                for (final mission in joinedMissions) ...[
                  SectionTile(
                    icon: Icons.task_alt_rounded,
                    title: _localizedMissionTitle(mission),
                    subtitle: _missionSubtitle(mission),
                    color: Colors.green,
                    onTap: () async {
                      final changed = await Get.to<bool>(
                      () => VolunteerMissionDetailScreen(
                        mission: mission,
                        alreadyJoined: true,
                        signupStatus: (mission['signup_status'] ?? '')
                            .toString(),
                      ),
                    );
                      if (changed == true && mounted) await _refresh();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              const SectionLabel(title: 'Available Missions'),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator()),
              if (loadError.isNotEmpty)
                SectionTile(
                  icon: Icons.assignment_turned_in_rounded,
                  title: 'Available Missions',
                  subtitle: loadError,
                  color: Colors.cyan,
                  onTap: _refresh,
                ),
              if (loadError.isEmpty &&
                  snapshot.connectionState != ConnectionState.waiting &&
                  missions.isEmpty)
                const SectionTile(
                  icon: Icons.assignment_turned_in_rounded,
                  title: 'Available Missions',
                  subtitle: 'No open volunteer missions are available yet.',
                  color: Colors.cyan,
                ),
              for (final mission in missions) ...[
                SectionTile(
                  icon: Icons.assignment_turned_in_rounded,
                  title: _localizedMissionTitle(mission),
                  subtitle: _missionSubtitle(mission),
                  color: Colors.cyan,
                  onTap: () async {
                    final signupStatus = _signupStatusFor(
                      mission,
                      joinedMissions,
                    );
                    final changed = await Get.to<bool>(
                      () => VolunteerMissionDetailScreen(
                        mission: mission,
                        alreadyJoined: signupStatus.isNotEmpty,
                        signupStatus: signupStatus,
                      ),
                    );
                    if (changed == true && mounted) await _refresh();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class VolunteerMissionDetailScreen extends StatefulWidget {
  const VolunteerMissionDetailScreen({
    super.key,
    required this.mission,
    required this.alreadyJoined,
    required this.signupStatus,
  });

  final Map<String, dynamic> mission;
  final bool alreadyJoined;
  final String signupStatus;

  @override
  State<VolunteerMissionDetailScreen> createState() =>
      _VolunteerMissionDetailScreenState();
}

class _VolunteerMissionDetailScreenState
    extends State<VolunteerMissionDetailScreen> {
  bool _loading = false;
  late bool _joined;
  late String _signupStatus;

  @override
  void initState() {
    super.initState();
    _joined = widget.alreadyJoined;
    _signupStatus = widget.signupStatus;
  }

  Future<void> _joinMission() async {
    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    final missionId = int.tryParse((widget.mission['id'] ?? '').toString());
    if (userId == null || userId <= 0 || missionId == null || missionId <= 0) {
      Get.snackbar('Error'.tr, 'Please sign in again before joining.'.tr);
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await const ModuleApi().joinVolunteerMission(
        userId: userId,
        missionId: missionId,
      );
      if (!mounted) return;
      final nextStatus = (response['status'] ?? 'pending').toString();
      setState(() {
        _joined = true;
        _signupStatus = nextStatus;
      });
      final message = switch (nextStatus) {
        'approved' => 'You are already approved for this mission.'.tr,
        'joined' => 'Your mission attendance is already recorded.'.tr,
        'completed' => 'This mission is already completed for you.'.tr,
        _ => 'Join request sent for admin approval.'.tr,
      };
      Get.snackbar('Submitted'.tr, message);
    } catch (e) {
      if (mounted) Get.snackbar('Error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = _localizedMissionDescription(widget.mission);
    return SectionScaffold(
      title: _localizedMissionTitle(widget.mission),
      subtitle: _missionSubtitle(widget.mission),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    InfoChip(
                      icon: Icons.location_on_rounded,
                      label: (widget.mission['city'] ?? 'Flexible').toString(),
                    ),
                    InfoChip(
                      icon: Icons.event_rounded,
                      label: (widget.mission['mission_date'] ?? 'Flexible')
                          .toString(),
                    ),
                    InfoChip(
                      icon: Icons.groups_rounded,
                      label: _missionCapacityLabel(widget.mission),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  description.trim().isEmpty
                      ? 'No mission description is available yet.'.tr
                      : description,
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loading || _joined ? null : _joinMission,
                    icon: Icon(
                      _joined
                          ? Icons.check_circle_rounded
                          : Icons.front_hand_rounded,
                    ),
                    label: Text(
                      _missionJoinButtonLabel(_signupStatus, _joined),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VolunteerApplicationFormScreen extends StatefulWidget {
  const VolunteerApplicationFormScreen({super.key});

  @override
  State<VolunteerApplicationFormScreen> createState() =>
      _VolunteerApplicationFormScreenState();
}

class _VolunteerApplicationFormScreenState
    extends State<VolunteerApplicationFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _skills = TextEditingController();
  final _experience = TextEditingController();
  final _availability = TextEditingController();
  bool _loading = false;

  // Phase 26 — structured chip selections and per-day availability map.
  // Free-form `_skills` and `_availability` controllers are kept for
  // anything the volunteer wants to add that doesn't fit a chip (e.g.
  // "I have a forklift license").
  Set<String> _selectedSkillKeys = <String>{};
  Map<String, DayAvailability> _schedule = <String, DayAvailability>{};

  @override
  void initState() {
    super.initState();
    _name.text = sharedPreferences.getString('name_user')?.trim() ?? '';
    _phone.text = sharedPreferences.getString('phone_user')?.trim() ?? '';
    _city.text =
        sharedPreferences.getString('city_user')?.trim().isNotEmpty == true
        ? sharedPreferences.getString('city_user')!.trim()
        : sharedPreferences.getString('address_user')?.trim() ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _skills.dispose();
    _experience.dispose();
    _availability.dispose();
    super.dispose();
  }

  String? _validate() {
    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    if (userId == null || userId <= 0) {
      return 'Please sign in again before submitting.'.tr;
    }

    for (final entry in {
      'Full name': _name.text,
      'Phone': _phone.text,
      'City': _city.text,
    }.entries) {
      if (entry.value.trim().isEmpty) {
        return 'Enter @field.'.trParams({'field': entry.key.tr});
      }
    }

    // Phase 26 — at least one channel for skills and availability. The
    // volunteer can use chips, free text, or both — but the application
    // can't be empty.
    if (_selectedSkillKeys.isEmpty && _skills.text.trim().isEmpty) {
      return 'Pick at least one skill or describe what you can do.'.tr;
    }
    if (_schedule.isEmpty && _availability.text.trim().isEmpty) {
      return 'Pick at least one day you are available.'.tr;
    }

    final digits = _phone.text.replaceAll(RegExp(r'[\s()+-]'), '');
    if (digits.length < 7) {
      return 'Enter a valid phone number.'.tr;
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      Get.snackbar('Error'.tr, error);
      return;
    }

    setState(() => _loading = true);
    try {
      // Phase 26 — payload now carries both the legacy free-form text
      // (for back-compat / "other" notes) and the structured
      // skill_tags + availability_schedule arrays.
      final scheduleJson = _orderedScheduleJson();
      await const ModuleApi().postJson(volunteerMissionsUrl, {
        'user_id': sharedPreferences.getString('id_user') ?? '',
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'city': _city.text.trim(),
        'skills': _skills.text.trim(),
        'experience': _experience.text.trim(),
        'availability': _availability.text.trim(),
        'skill_tags': _selectedSkillKeys.toList(growable: false),
        'availability_schedule': scheduleJson,
      });
      await sharedPreferences.setString('phone_user', _phone.text.trim());
      await sharedPreferences.setString('city_user', _city.text.trim());
      if (!mounted) return;
      if (Get.isRegistered<NotificationsController>()) {
        await Get.find<NotificationsController>().refreshNotifications();
      }
      Get.back<bool>(result: true);
      Get.snackbar('Submitted'.tr, 'Volunteer application saved.'.tr);
    } catch (e) {
      if (mounted) Get.snackbar('Error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Serialize the schedule map → list of `{day,from,to}` ordered mon..sun.
  /// Backend re-validates / dedupes, but sending the canonical order makes
  /// the admin-side "what days" display deterministic.
  List<Map<String, String>> _orderedScheduleJson() {
    const order = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final out = <Map<String, String>>[];
    for (final d in order) {
      final entry = _schedule[d];
      if (entry != null) out.add(entry.toJson());
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Volunteer application',
      subtitle: 'Tell the institution how you can help.',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _VolunteerTextField(controller: _name, label: 'Full name'),
                _VolunteerTextField(
                  controller: _phone,
                  label: 'Phone',
                  keyboardType: TextInputType.phone,
                ),
                _VolunteerTextField(controller: _city, label: 'City'),
                const SizedBox(height: 12),
                _SectionLabel(
                  icon: Icons.stars_rounded,
                  title: 'Your skills'.tr,
                  subtitle: 'Tap to open the picker.'.tr,
                ),
                SkillPickerField(
                  selectedKeys: _selectedSkillKeys,
                  onChanged: (next) =>
                      setState(() => _selectedSkillKeys = next),
                ),
                const SizedBox(height: 4),
                _VolunteerTextField(
                  controller: _skills,
                  label: 'Other skills (anything not listed)',
                  maxLines: 2,
                ),
                _VolunteerTextField(
                  controller: _experience,
                  label: 'Experience',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _SectionLabel(
                  icon: Icons.event_available_rounded,
                  title: 'When you\'re available'.tr,
                  subtitle: 'Pick days and hours, or use a quick preset.'.tr,
                ),
                AvailabilitySchedulePicker(
                  schedule: _schedule,
                  onChanged: (next) => setState(() => _schedule = next),
                ),
                const SizedBox(height: 4),
                _VolunteerTextField(
                  controller: _availability,
                  label: 'Availability notes (optional)',
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Submit application'.tr),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header above the chip / schedule blocks. Two-line layout with
/// a leading round icon, bold title, and muted helper subtitle.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.disabledColor,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VolunteerTextField extends StatelessWidget {
  const _VolunteerTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label.tr),
      ),
    );
  }
}

List<Map<String, dynamic>> _listFrom(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

String _localizedMissionTitle(Map<String, dynamic> mission) {
  final isArabic = Get.locale?.languageCode.toLowerCase() == 'ar';
  final preferred = (mission[isArabic ? 'title_ar' : 'title'] ?? '')
      .toString()
      .trim();
  if (preferred.isNotEmpty) return preferred;
  final alternate = (mission[isArabic ? 'title' : 'title_ar'] ?? '')
      .toString()
      .trim();
  return alternate.isEmpty ? 'Volunteer mission'.tr : alternate;
}

String _localizedMissionDescription(Map<String, dynamic> mission) {
  final isArabic = Get.locale?.languageCode.toLowerCase() == 'ar';
  final preferred = (mission[isArabic ? 'description_ar' : 'description'] ?? '')
      .toString()
      .trim();
  if (preferred.isNotEmpty) return preferred;
  return (mission[isArabic ? 'description' : 'description_ar'] ?? '')
      .toString()
      .trim();
}

String _missionSubtitle(Map<String, dynamic> mission) {
  return [
    (mission['city'] ?? '').toString(),
    (mission['mission_date'] ?? 'Flexible').toString(),
    _missionCapacityLabel(mission),
    if ((mission['signup_status'] ?? '').toString().isNotEmpty)
      (mission['signup_status'] ?? '').toString(),
  ].where((value) => value.trim().isNotEmpty).join(' - ');
}

String _applicationSubtitle(Map<String, dynamic> application) {
  return [
    (application['status'] ?? 'submitted').toString().replaceAll('_', ' '),
    (application['city'] ?? '').toString(),
    (application['availability'] ?? '').toString(),
  ].where((value) => value.trim().isNotEmpty).join(' - ');
}

Color _applicationColor(String status) {
  return switch (status) {
    'approved' => Colors.green,
    'rejected' => Colors.redAccent,
    'inactive' => Colors.orange,
    _ => Colors.indigo,
  };
}

String _signupStatusFor(
  Map<String, dynamic> mission,
  List<Map<String, dynamic>> joinedMissions,
) {
  final missionId = (mission['id'] ?? '').toString();
  for (final item in joinedMissions) {
    if ((item['id'] ?? '').toString() == missionId) {
      return (item['signup_status'] ?? '').toString();
    }
  }
  return '';
}

String _missionCapacityLabel(Map<String, dynamic> mission) {
  final needed =
      int.tryParse((mission['needed_volunteers'] ?? '').toString()) ?? 0;
  final accepted =
      int.tryParse((mission['accepted_volunteers'] ?? '').toString()) ?? 0;
  final pending =
      int.tryParse((mission['pending_volunteers'] ?? '').toString()) ?? 0;
  if (needed <= 0) {
    return pending > 0 ? '$pending pending' : '';
  }
  final pendingText = pending > 0 ? ', $pending pending' : '';
  return '$accepted / $needed volunteers$pendingText';
}

String _missionJoinButtonLabel(String status, bool joined) {
  return switch (status) {
    'pending' => 'Request pending'.tr,
    'approved' || 'joined' => 'Accepted'.tr,
    'completed' => 'Completed'.tr,
    'cancelled' => 'Cancelled'.tr,
    _ => joined ? 'Already requested'.tr : 'Join mission'.tr,
  };
}
