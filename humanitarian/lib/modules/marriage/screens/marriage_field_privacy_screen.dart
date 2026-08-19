// L19 — per-field privacy on the engagement ("خطوبتي") profile.
//
// WHY THIS SCREEN DID NOT EXIST UNTIL NOW
// The engagement form offers ONE whole-profile audience dropdown with three
// values (`visibility_level`), which cannot express "show my age, hide my
// photo". A per-field picker was deliberately NOT shipped, and that was the
// right call: `marriage.Store.List` selected every field and masked none, so
// the switches would have changed nothing. On a matchmaking profile that is a
// privacy incident dressed as a feature.
//
// WHAT CHANGED
// Backend 0206ca0 + migration 107 added `marriage_profiles.field_privacy`, the
// `marriage_privacy_field_options` catalogue, and — the part that makes this
// honest — `maskForViewer`, which blanks the named fields for anyone who is
// not the owner, across all four callers (browse, mine, saved, subscription).
//
// THE CATALOGUE IS THE CONTRACT
// `SetFieldPrivacy` drops any key the catalogue does not list. So this screen
// renders the server's list and NOTHING else: no built-in fallback, unlike the
// user-profile privacy screen. A fallback here could offer a switch for an
// option staff had retired, and that switch would post a key the server
// discards — a control that silently does nothing, which is precisely what
// L19 was refused over the first time.
//
// WHERE THE CURRENT STATE COMES FROM
// The owner's own `field_privacy` rides along on GET /api/marriage/mine (it is
// served to the owner and emptied for everybody else), so the caller passes it
// in. There is no second fetch to fail, and no moment where the screen has to
// guess — guessing "nothing is hidden" is the one default a privacy screen may
// not have.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Placeholder bones shaped like one switch row, so the controls fill in
/// rather than pop in over a spinner.
class _PrivacyRowBones extends StatelessWidget {
  const _PrivacyRowBones();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSkeleton.bone(height: 12, widthFactor: 0.45),
                AppSkeleton.bone(height: 9, widthFactor: 0.3),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(width: 44, child: AppSkeleton.bone(height: 22)),
        ],
      ),
    );
  }
}

/// Which details of one engagement profile other people can see.
class MarriageFieldPrivacyScreen extends StatefulWidget {
  const MarriageFieldPrivacyScreen({
    super.key,
    required this.profileId,
    required this.initialHidden,
  });

  /// `marriage_profiles.id`. It goes in the POST path, where ownership is
  /// checked inside the UPDATE.
  final int profileId;

  /// The field keys this profile already hides, straight from the same
  /// `GET /api/marriage/mine` response that drew the card this screen opened
  /// from.
  final List<String> initialHidden;

  @override
  State<MarriageFieldPrivacyScreen> createState() =>
      _MarriageFieldPrivacyScreenState();
}

class _MarriageFieldPrivacyScreenState
    extends State<MarriageFieldPrivacyScreen> {
  /// The catalogue, or null before the first load — null rather than `const []`
  /// so AppAsync shows a skeleton first rather than "nothing to control".
  List<PrivacyFieldOption>? _options;

  late final Set<String> _hidden = {...widget.initialHidden};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final options = await const ModuleApi().getMarriagePrivacyOptions();
      if (mounted) setState(() => _options = options);
    } catch (e) {
      if (!mounted) return;
      // Reuses the user-profile privacy screen's wording — it is the same
      // sentence about the same kind of list, and it already has Arabic.
      setState(
        () => _error = 'Could not refresh the list of fields you can hide.',
      );
      debugPrint('getMarriagePrivacyOptions failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shows or hides one field. `visible` false means the key goes into
  /// `field_privacy`.
  Future<void> _toggle(String key, bool visible) async {
    AppHaptics.selection();
    final previous = Set<String>.from(_hidden);
    setState(() {
      if (visible) {
        _hidden.remove(key);
      } else {
        _hidden.add(key);
      }
      _saving = true;
    });
    try {
      // The WHOLE set. SetFieldPrivacy writes the column outright, so posting
      // only the field just switched would un-hide every other one.
      final saved = await const ModuleApi().setMarriageFieldPrivacy(
        widget.profileId,
        _hidden.toList(),
      );
      if (!mounted) return;
      setState(() {
        _hidden
          ..clear()
          ..addAll(saved);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hidden
          ..clear()
          ..addAll(previous);
      });
      // The server's own message is English ("This engagement profile is not
      // yours."), and this screen is read in Arabic — so the technical detail
      // goes to the log and the user gets a localized sentence. A switch that
      // flips back with no word reads as broken rather than as a save that
      // failed.
      debugPrint('setMarriageFieldPrivacy(${widget.profileId}) failed: $e');
      Get.snackbar(
        'Field privacy'.tr,
        'Could not save that preference. Please try again.'.tr,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Field privacy',
      subtitle: 'privacy_desc',
      child: AppAsync<List<PrivacyFieldOption>>(
        // The gutter lives inside this screen's own list, so the skeleton
        // and the error banner would otherwise sit edge-to-edge while the
        // content that replaces them sits in a 20pt margin.
        gutter: const EdgeInsets.symmetric(horizontal: 20),
        loading: _loading,
        error: _error,
        onRetry: _load,
        data: _options,
        isEmpty: (options) => options.isEmpty,
        skeleton: const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: AppSkeleton(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PrivacyRowBones(),
                _PrivacyRowBones(),
                _PrivacyRowBones(),
                _PrivacyRowBones(),
              ],
            ),
          ),
        ),
        // Reachable: staff can retire every row of the catalogue. Not an
        // error, and not the user's doing — so it says what it means for
        // them, which is that the profile shows what it shows today.
        empty: AppEmpty(
          title: 'marriage_privacy_empty'.tr,
          message: 'marriage_privacy_empty_desc'.tr,
          icon: Icons.visibility_off_outlined,
        ),
        builder: (options) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            for (final o in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassPanel(
                  child: SwitchListTile.adaptive(
                    key: Key('marriage_privacy_${o.fieldKey}'),
                    contentPadding: EdgeInsets.zero,
                    value: !_hidden.contains(o.fieldKey),
                    onChanged: _saving ? null : (v) => _toggle(o.fieldKey, v),
                    title: Text(
                      // Server data, so localizedTag rather than `.tr`, which
                      // hands the key back when there is no entry.
                      localizedTag(o.labelKey),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      _hidden.contains(o.fieldKey)
                          ? 'privacy_hidden'.tr
                          : 'privacy_visible'.tr,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
