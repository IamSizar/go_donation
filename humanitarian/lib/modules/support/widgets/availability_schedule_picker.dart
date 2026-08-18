// Phase 26 — per-day availability picker for the volunteer application form.
//
// v2 design (Phase 26.1): three-part layout
//   1. Preset chips (Weekdays / Weekends / Every day / Clear)
//   2. 7 day pills (Mon..Sun) — tap to toggle a day on/off
//   3. Per-active-day time row showing From → To, each opening a
//      time picker; remove button to deselect the day inline.
//
// The parent owns the canonical state as Map<dayKey, DayAvailability>.

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/design/motion.dart';

/// One day's availability slice. The day key must be one of mon..sun.
class DayAvailability {
  const DayAvailability({
    required this.day,
    required this.from,
    required this.to,
  });

  final String day; // 'mon' .. 'sun'
  final TimeOfDay from;
  final TimeOfDay to;

  DayAvailability copyWith({TimeOfDay? from, TimeOfDay? to}) =>
      DayAvailability(day: day, from: from ?? this.from, to: to ?? this.to);

  /// Backend wire format: { day, from: "HH:MM", to: "HH:MM" }.
  Map<String, String> toJson() => {
    'day': day,
    'from': fmt(from),
    'to': fmt(to),
  };

  // ─── The wire/display boundary ───
  //
  // These two functions look like duplicates and are not. They format the same
  // TimeOfDay for two audiences that must not be given the same string, and
  // the whole point of keeping them adjacent is that the next person to reach
  // for one is shown the other.
  //
  // [fmt] is the STORED value. It is 24-hour, zero-padded, locale-independent
  // and must stay that way: `toJson` writes it, the Go backend stores it, and
  // the admin dashboard's `scheduleSummary`
  // (admin-web/src/lib/skillCatalogue.ts) prints the `from`/`to` strings
  // verbatim into what a caseworker reads. So the column is shared, not ours.
  // A 12-hour string — or an Arabic AM/PM marker — written into it would make
  // the stored data depend on the language of the phone that saved it, and
  // would surface untranslated on the other end. Nothing that renders to a
  // screen should call it.
  //
  // [display] is the SHOWN value — 12-hour and localized. Everything the user
  // reads goes through it. Originally there was only [fmt], used for both, and
  // that is precisely why the app painted the wire format ("09:00-17:00") onto
  // the volunteer's card and into the picker's own buttons.

  /// HH:MM (24h) — the STORED format. `toJson` only; never rendered.
  /// See the boundary note above before using this in UI code.
  static String fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// The same time as the reader should see it — "9:00 AM", «9:00 ص».
  ///
  /// Routed through [fmt] rather than reading `t.hour`/`t.minute` a second
  /// time so that there is exactly one description of what a TimeOfDay means
  /// in this app, and the display can never disagree with what was stored.
  static String display(TimeOfDay t) => localizedClockTime(fmt(t));
}

const List<String> _dayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// Short (3-char) day labels per locale. Used inside the day pills.
/// A localized, comma-separated summary of a stored availability schedule.
///
/// WHY THIS EXISTS
/// The application card printed the `availability` column verbatim, and that
/// column holds the free-text summary the FORM produced — which was built with
/// English day names. So an Arabic screen showed "Mon 09:00-17:00, Tue …", and
/// no display-time `.tr` could fix it: the English was already in the data.
///
/// The structured `availability_schedule` is stored alongside it and holds day
/// KEYS, which do localize. Rendering from that instead means the card follows
/// the reader's language rather than the language whoever filled the form was
/// using.
///
/// Returns '' when the schedule is missing or unusable, so the caller can fall
/// back to the stored text rather than show nothing.
/// Which column of [_dayShort] this reader gets.
///
/// Kurdish cannot be told from the language code alone — both variants ride on
/// Arabic locales and are separated by script — so this is the one place that
/// decision is made, shared by the picker and the summary below. Duplicating it
/// is how the two would drift into disagreeing about what language a Badini
/// reader is using.
String resolveScheduleLocale() {
  final code = Get.locale?.languageCode ?? 'en';
  final script = Get.locale?.scriptCode;
  if (script == 'Arab') return 'ckb';
  if (script == 'Latn' && code == 'ku') return 'kmr';
  return code;
}

String localizedScheduleSummary(Object? schedule, [String? locale]) {
  final lang = locale ?? resolveScheduleLocale();
  if (schedule is! List) return '';
  final parts = <String>[];
  for (final entry in schedule) {
    if (entry is! Map) continue;
    final day = (entry['day'] ?? '').toString();
    final label = _dayShort[day]?[lang] ?? _dayShort[day]?['en'];
    if (label == null) continue;
    // The stored ends are 24-hour "HH:MM" — the wire format. They are
    // reformatted for reading here rather than interpolated raw, which is what
    // put "Mon 09:00-17:00" on the card. `isolatedClockRange` also returns ''
    // when either end is missing, which is the same degrade-to-the-day-name
    // behaviour the raw version had to spell out with an isEmpty check.
    final hours = isolatedClockRange(entry['from'], entry['to']);
    parts.add(hours.isEmpty ? label : '$label $hours');
  }
  return parts.join('، ');
}

const Map<String, Map<String, String>> _dayShort = {
  'mon': {'en': 'Mon', 'ar': 'إثن', 'ckb': 'دوو', 'kmr': 'دوو'},
  'tue': {'en': 'Tue', 'ar': 'ثلا', 'ckb': 'سێش', 'kmr': 'سێش'},
  'wed': {'en': 'Wed', 'ar': 'أرب', 'ckb': 'چوا', 'kmr': 'چوا'},
  'thu': {'en': 'Thu', 'ar': 'خمي', 'ckb': 'پێن', 'kmr': 'پێن'},
  'fri': {'en': 'Fri', 'ar': 'جمع', 'ckb': 'هەی', 'kmr': 'هەی'},
  'sat': {'en': 'Sat', 'ar': 'سبت', 'ckb': 'شەم', 'kmr': 'شەم'},
  'sun': {'en': 'Sun', 'ar': 'أحد', 'ckb': 'یەک', 'kmr': 'یەک'},
};

/// Full day labels for the time picker rows.
const Map<String, Map<String, String>> _dayLong = {
  'mon': {'en': 'Monday', 'ar': 'الإثنين', 'ckb': 'دووشەممە', 'kmr': 'دووشەم'},
  'tue': {'en': 'Tuesday', 'ar': 'الثلاثاء', 'ckb': 'سێشەممە', 'kmr': 'سێشەم'},
  'wed': {
    'en': 'Wednesday',
    'ar': 'الأربعاء',
    'ckb': 'چوارشەممە',
    'kmr': 'چوارشەم',
  },
  'thu': {
    'en': 'Thursday',
    'ar': 'الخميس',
    'ckb': 'پێنجشەممە',
    'kmr': 'پێنجشەم',
  },
  'fri': {'en': 'Friday', 'ar': 'الجمعة', 'ckb': 'هەینی', 'kmr': 'هەینی'},
  'sat': {'en': 'Saturday', 'ar': 'السبت', 'ckb': 'شەممە', 'kmr': 'شەممی'},
  'sun': {'en': 'Sunday', 'ar': 'الأحد', 'ckb': 'یەکشەممە', 'kmr': 'یەکشەم'},
};

class AvailabilitySchedulePicker extends StatelessWidget {
  const AvailabilitySchedulePicker({
    super.key,
    required this.schedule,
    required this.onChanged,
  });

  /// Days not in the map = unavailable. Day key → from/to.
  final Map<String, DayAvailability> schedule;
  final ValueChanged<Map<String, DayAvailability>> onChanged;

  String _resolveLocale() => resolveScheduleLocale();

  // Default work day used by all presets + first-time toggles.
  static const _defaultFrom = TimeOfDay(hour: 9, minute: 0);
  static const _defaultTo = TimeOfDay(hour: 17, minute: 0);

  void _toggleDay(String day, bool active) {
    final next = Map<String, DayAvailability>.from(schedule);
    if (active) {
      // Use the existing times if the volunteer is re-enabling a day they
      // previously turned off in this session — otherwise default 9-5.
      next[day] =
          schedule[day] ??
          DayAvailability(day: day, from: _defaultFrom, to: _defaultTo);
    } else {
      next.remove(day);
    }
    onChanged(next);
  }

  Future<void> _pickTime(BuildContext context, String day, bool isFrom) async {
    final current = schedule[day];
    final initial = isFrom
        ? (current?.from ?? _defaultFrom)
        : (current?.to ?? _defaultTo);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final existing =
        schedule[day] ??
        DayAvailability(day: day, from: _defaultFrom, to: _defaultTo);
    final next = Map<String, DayAvailability>.from(schedule);
    next[day] = isFrom
        ? existing.copyWith(from: picked)
        : existing.copyWith(to: picked);
    onChanged(next);
  }

  void _applyPreset(List<String> days) {
    final next = <String, DayAvailability>{};
    for (final d in days) {
      next[d] = DayAvailability(day: d, from: _defaultFrom, to: _defaultTo);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final locale = _resolveLocale();
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Quick presets ----
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _PresetChip(
              icon: Icons.work_outline_rounded,
              label: 'Weekdays 9–5'.tr,
              accent: primary,
              onTap: () =>
                  _applyPreset(const ['mon', 'tue', 'wed', 'thu', 'fri']),
            ),
            _PresetChip(
              icon: Icons.beach_access_rounded,
              label: 'Weekends'.tr,
              accent: primary,
              onTap: () => _applyPreset(const ['sat', 'sun']),
            ),
            _PresetChip(
              icon: Icons.calendar_month_rounded,
              label: 'Every day'.tr,
              accent: primary,
              onTap: () => _applyPreset(_dayKeys),
            ),
            if (schedule.isNotEmpty)
              _PresetChip(
                icon: Icons.close_rounded,
                label: 'Clear'.tr,
                accent: theme.colorScheme.error,
                onTap: () => onChanged(<String, DayAvailability>{}),
              ),
          ],
        ),
        const SizedBox(height: 14),

        // ---- Day pills ----
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _dayKeys
              .map((d) {
                final active = schedule.containsKey(d);
                final short = _dayShort[d]?[locale] ?? _dayShort[d]!['en']!;
                return _DayPill(
                  short: short,
                  selected: active,
                  accent: primary,
                  onTap: () => _toggleDay(d, !active),
                );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: 14),

        // ---- Per-day time rows (only for active days) ----
        if (schedule.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: theme.disabledColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap a day above to set when you\'re available.'.tr,
                    style: TextStyle(
                      color: theme.disabledColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: _dayKeys
                .where((d) => schedule.containsKey(d))
                .map(
                  (d) => _TimeRow(
                    dayName: _dayLong[d]?[locale] ?? _dayLong[d]!['en']!,
                    from: schedule[d]!.from,
                    to: schedule[d]!.to,
                    accent: primary,
                    onFromTap: () => _pickTime(context, d, true),
                    onToTap: () => _pickTime(context, d, false),
                    onRemove: () => _toggleDay(d, false),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

/// A preset shortcut chip (Weekdays / Weekends / Every day / Clear).
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One 3-letter day pill. Filled when the volunteer is available that day.
class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.short,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String short;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(99),
            child: AnimatedContainer(
              duration: AppMotion.resolve(context, AppMotion.snapDuration),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: selected ? accent : accent.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Center(
                child: Text(
                  short,
                  style: TextStyle(
                    color: selected ? Colors.white : accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the active-days list: "Monday  [9:00 AM] → [5:00 PM]  ✕".
///
/// The bracketed labels used to read "09:00" and "17:00" — this row rendered
/// the stored 24-hour value directly. They now go through
/// [DayAvailability.display]; the times the row WRITES are unchanged.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.dayName,
    required this.from,
    required this.to,
    required this.accent,
    required this.onFromTap,
    required this.onToTap,
    required this.onRemove,
  });

  final String dayName;
  final TimeOfDay from;
  final TimeOfDay to;
  final Color accent;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              dayName,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            // `display`, not `fmt`: this is a label the volunteer reads, and
            // it was showing them the value the backend stores. Each button is
            // its own Text with nothing bidi-neutral beside it, so it needs no
            // isolate — only the joined summary does.
            child: _TimeButton(
              label: DayAvailability.display(from),
              accent: accent,
              onTap: onFromTap,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              AppIcons.forwardSolid(context),
              size: 16,
              color: theme.disabledColor,
            ),
          ),
          Expanded(
            child: _TimeButton(
              label: DayAvailability.display(to),
              accent: accent,
              onTap: onToTap,
            ),
          ),
          IconButton(
            tooltip: 'Remove day'.tr,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, color: theme.disabledColor),
          ),
        ],
      ),
    );
  }
}

/// One time button — opens the platform time picker on tap.
class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.access_time_rounded, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
