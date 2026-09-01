// required_fields_prompt.dart — owner item #16, the part that protects people
// who already registered.
//
// THE PROBLEM THIS SOLVES
// Staff can now mark a registration field REQUIRED from the dashboard, and the
// rule is per ROLE: it lands on everybody with that role, including the people
// who signed up months ago when the field did not exist or was optional. The
// obvious implementation — validate the rule on every screen — would lock
// thousands of people out of an app they already use because somebody flipped
// a switch. The owner's decision was explicit and is the whole design here:
//
//   EXISTING USERS ARE PROMPTED, NEVER BLOCKED.
//
// So this is a banner, not a gate. It:
//
//   • appears above the dashboard when the user's role now requires a field
//     their profile has not filled in,
//   • offers one action — open the profile screen and fill it in,
//   • can be dismissed, and dismissing it is final for that set of fields,
//   • never blocks, never intercepts navigation, and never returns anything a
//     caller could use to block.
//
// WHAT "FINAL FOR THAT SET" MEANS, AND WHY NOT "FINAL FOREVER"
// The dismissal is stored against a SIGNATURE of the missing fields (their
// sorted keys). Dismissing "you're missing a national ID" suppresses exactly
// that; if staff later make a SECOND field required, the signature changes and
// the person is told once about the new one. Storing a single boolean would
// mean the first dismissal silences every future request forever — which is
// not "do not nag", it is "never ask again", and staff would have no way to
// reach anyone. Storing nothing would nag on every launch, which is how a
// prompt gets dismissed without being read.
//
// WHY THE PROFILE READ IS BEST-EFFORT
// Everything here is advisory. If the rules or the account cannot be loaded,
// the banner simply does not appear — the user is not told something untrue
// about their own account, and nothing they were doing is interrupted.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/api/registration_api.dart';
import 'package:flutter_application_1/core/app_state.dart';

/// The prefs key holding the signature of the last dismissed prompt.
const String kRequiredFieldsPromptDismissedKey =
    'required_fields_prompt_dismissed';

/// Rule-key prefixes, one per app role. Mirrors `fieldRulePrefixForRole` in
/// backend/internal/handlers/field_rule_columns.go and `rulePrefixForRole` in
/// admin-web/src/lib/fieldRuleColumns.ts — three copies of one convention,
/// because each side has to resolve it without calling the others.
String? rulePrefixForRole(int roleId) {
  switch (roleId) {
    case 1:
      return 'grantor_';
    case 2:
      return 'recipient_';
    case 3:
      return 'volunteer_';
    default:
      // A role with no registration form has no rules that could apply.
      return null;
  }
}

const List<String> _allRulePrefixes = <String>[
  'grantor_',
  'recipient_',
  'volunteer_',
  'marriage_',
  'case_',
  'user_',
];

/// Strips whichever namespace prefix a rule key carries.
String ruleKeySuffix(String key) {
  for (final p in _allRulePrefixes) {
    if (key.startsWith(p)) return key.substring(p.length);
  }
  return key;
}

/// The account-map field(s) one rule key is answered by.
///
/// Same five irregular shapes the server and the dashboard resolve; see
/// backend/internal/handlers/field_rule_columns.go for why each exists.
List<String> columnsForRuleKey(String key) {
  final suffix = ruleKeySuffix(key);
  switch (suffix) {
    case 'name_parts':
      return const ['name_first', 'name_father', 'name_grandfather', 'name_family'];
    case 'gps_location':
      return const ['gps_lat', 'gps_lng'];
    case 'personal_photo':
      return const ['profile_picture'];
    case 'household_disabled':
      return const ['household_disabled_count'];
    case 'household_employees':
      return const ['household_employees_count'];
    case 'working_members':
      return const ['working_members_count'];
  }
  if (suffix.endsWith('_photo')) return ['${suffix}_path'];
  return [suffix];
}

/// True when the account map holds nothing usable for this key.
///
/// A key is satisfied when EVERY column it maps to has a value: a "full name"
/// with three of its four parts filled in is not a filled-in full name, and
/// telling the user it is would send them to a screen with nothing to do.
bool _isMissing(String ruleKey, Map<String, dynamic> account) {
  for (final col in columnsForRuleKey(ruleKey)) {
    final v = account[col];
    if (v == null) return true;
    if (v is String && v.trim().isEmpty) return true;
    if (v is num && col.startsWith('gps_') && v == 0) {
      // 0/0 is the null island, not a location anybody stood on — it is what
      // the column holds when the phone never reported a fix.
      return true;
    }
  }
  return false;
}

/// The rule keys this role must now answer and this account has not.
///
/// Pure, so the whole decision is testable without a network or a widget.
/// Hidden fields are excluded even if also flagged required: a field the form
/// does not render cannot be filled in, so demanding it would be a dead end —
/// the same exclusion registration_form.dart applies at submit time.
List<String> missingRequiredFields({
  required int roleId,
  required FieldRuleSets rules,
  required Map<String, dynamic> account,
}) {
  final prefix = rulePrefixForRole(roleId);
  final out = <String>[];
  for (final key in rules.required) {
    if (rules.hidden.contains(key)) continue;
    final prefixed = _allRulePrefixes.any(key.startsWith);
    // The key applies if it is in this role's namespace, or is unprefixed —
    // the shared sign-up step every role passes through.
    final applies = (prefix != null && key.startsWith(prefix)) || !prefixed;
    if (!applies) continue;
    if (_isMissing(key, account)) out.add(key);
  }
  out.sort(); // Stable, so the dismissal signature below is stable.
  return out;
}

/// The dismissal signature for a set of missing fields. Sorted and joined, so
/// the same set always produces the same string and a CHANGED set does not.
String promptSignature(List<String> missing) => missing.join(',');

/// Whether this exact set of missing fields has already been dismissed.
bool isPromptDismissed(List<String> missing) =>
    sharedPreferences.getString(kRequiredFieldsPromptDismissedKey) ==
    promptSignature(missing);

/// Records that the user dismissed this exact set.
Future<void> dismissPrompt(List<String> missing) =>
    sharedPreferences.setString(
      kRequiredFieldsPromptDismissedKey,
      promptSignature(missing),
    );

/// Loads the rules and the account. Injected in tests; best-effort in
/// production — either half failing simply means no banner.
typedef RequiredFieldsLoader = Future<List<String>> Function();

Future<List<String>> _loadMissingFields() async {
  final roleId = int.tryParse(sharedPreferences.getString('role_id') ?? '') ?? 0;
  if (rulePrefixForRole(roleId) == null) return const [];
  final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;
  if (userId <= 0) return const [];
  final rules = await fetchFieldRuleSets();
  if (rules.required.isEmpty) return const [];
  final account = await fetchUserAccount(userId);
  if (account == null) {
    // NOT swallowed — it is the documented "cannot say" signal from
    // fetchUserAccount. Showing a banner here would mean telling someone their
    // profile is incomplete on the strength of a request that failed.
    return const [];
  }
  return missingRequiredFields(roleId: roleId, rules: rules, account: account);
}

/// The banner itself.
///
/// Renders NOTHING at all until it knows there is something to say: no
/// skeleton, no spinner, no reserved space. This is not one of the four states
/// of a content area — it is an interruption, and an interruption that
/// announces itself before it has anything to announce is just a flicker at
/// the top of the screen on every launch.
class RequiredFieldsPrompt extends StatefulWidget {
  const RequiredFieldsPrompt({super.key, this.loader, this.onOpenProfile});

  /// Overridden in tests. Defaults to the real rules + account fetch.
  final RequiredFieldsLoader? loader;

  /// What "Complete it" does. Defaults to the profile route.
  final VoidCallback? onOpenProfile;

  @override
  State<RequiredFieldsPrompt> createState() => _RequiredFieldsPromptState();
}

class _RequiredFieldsPromptState extends State<RequiredFieldsPrompt> {
  List<String> _missing = const [];
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loader = widget.loader ?? _loadMissingFields;
    List<String> missing;
    try {
      missing = await loader();
    } catch (_) {
      // Advisory to the last: a failure here must never reach the user, who
      // did nothing and can do nothing about it. The banner stays hidden.
      missing = const [];
    }
    if (!mounted) return;
    setState(() {
      _missing = missing;
      _dismissed = missing.isEmpty || isPromptDismissed(missing);
    });
  }

  Future<void> _dismiss() async {
    await dismissPrompt(_missing);
    if (!mounted) return;
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _missing.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      // 16/12 — the app's spacing scale. Logical insets only, so the banner
      // mirrors correctly in Arabic and Kurdish.
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'required_fields_prompt_title'.tr,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'required_fields_prompt_body'.tr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // 44x44 minimum touch targets on both actions — the
                      // dismiss especially, because a dismiss that is hard to
                      // hit is a prompt that blocks in practice.
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                        child: TextButton(
                          onPressed: widget.onOpenProfile ?? () => Get.toNamed('/profile'),
                          child: Text('required_fields_prompt_action'.tr),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                        child: TextButton(
                          onPressed: _dismiss,
                          child: Text('required_fields_prompt_dismiss'.tr),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
