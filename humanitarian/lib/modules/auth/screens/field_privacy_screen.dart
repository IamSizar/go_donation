import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:get/get.dart';

/// Placeholder bones shaped like one privacy switch row: a label line, a
/// state line, and the block the switch itself occupies. Extracted so the
/// loading state can be a `const` widget alongside the real rows it mimics.
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
                AppSkeleton.bone(height: 12, widthFactor: 0.5),
                AppSkeleton.bone(height: 9, widthFactor: 0.32),
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

/// #32 — Field privacy: the user chooses which of their profile fields are
/// public or hidden. A field is "hidden" when its key is in the stored list;
/// the switch shows ON = visible. Saved to /api/profile/privacy.
class FieldPrivacyScreen extends StatefulWidget {
  const FieldPrivacyScreen({super.key});

  @override
  State<FieldPrivacyScreen> createState() => _FieldPrivacyScreenState();
}

class _FieldPrivacyScreenState extends State<FieldPrivacyScreen> {
  // The profile fields a user may hide, with their label keys.
  /// Offline/failure fallback only. The live list comes from
  /// GET /api/profile/privacy-options so staff can add or retire options
  /// without an app change (Privacy Settings spec, "Future Development").
  static const _fallbackFields = <({String key, String labelKey})>[
    (key: 'full_name', labelKey: 'pf_full_name'),
    (key: 'phone', labelKey: 'pf_phone'),
    (key: 'gender', labelKey: 'pf_gender'),
    (key: 'address', labelKey: 'pf_address'),
    (key: 'date_of_birth', labelKey: 'pf_dob'),
    (key: 'profile_picture', labelKey: 'pf_picture'),
  ];

  List<({String key, String labelKey})> _fields = _fallbackFields;

  final _hidden = <String>{};
  bool _loading = true;
  bool _saving = false;

  /// Set when the user's stored hidden-field list could not be fetched.
  ///
  /// THIS ONE IS A SAFETY GATE, NOT DECORATION. Every switch renders as
  /// `!_hidden.contains(key)`, so an empty `_hidden` draws every field ON —
  /// "Visible". When the fetch has simply failed, that is not a neutral
  /// default: it shows a user their private fields as PUBLIC. They may then
  /// leave believing the profile is exposed, or worse, toggle something and
  /// have `_toggle` POST that empty set back as the truth, actually unhiding
  /// every field they had hidden. While this is non-null the toggle list is
  /// not rendered at all.
  String? _hiddenError;

  /// Set when the admin-managed option catalogue could not be fetched.
  ///
  /// Deliberately NOT a gate. The built-in `_fallbackFields` list stands in,
  /// which states nothing untrue about the user's own settings — it only risks
  /// omitting a field staff added recently. So this surfaces as a banner ABOVE
  /// a fully working list rather than in place of it: hiding usable privacy
  /// controls behind an error would be its own harm.
  String? _optionsError;

  // Privacy Settings spec — display-name choice + social links.
  String _displayNameMode = 'real';
  final _aliasController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _telegramController = TextEditingController();
  bool _savingExtras = false;

  /// Set when the display-name/social fetch failed. While it is non-null the
  /// on-screen values are NOT known to match the server, so saving is blocked
  /// — see the comment in [_loadExtras].
  String? _extrasError;

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _load();
    _loadExtras();
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _telegramController.dispose();
    super.dispose();
  }

  /// Reloads both halves of the toggle list — the option catalogue and the
  /// user's stored choices. The retry action for either failure, so one tap
  /// recovers the screen whichever request dropped.
  Future<void> _reloadFields() async {
    await Future.wait([_loadOptions(), _load()]);
  }

  /// Fetches which of the user's fields are currently hidden.
  Future<void> _load() async {
    // Cleared before the attempt so a successful retry cannot leave the old
    // failure gating a list that has since loaded correctly.
    if (_hiddenError != null) setState(() => _hiddenError = null);
    try {
      final hidden = await const ModuleApi().getFieldPrivacy();
      if (mounted) setState(() => _hidden.addAll(hidden));
    } catch (e) {
      // Was `catch (_) {}` under the comment "Keep everything visible if the
      // fetch fails." That is the one fallback a privacy screen may not have:
      // it renders the user's hidden fields as public. Fail closed instead —
      // record the error, show no switches, and offer a retry.
      if (mounted) {
        setState(() => _hiddenError = 'Could not load your privacy settings.');
      }
      debugPrint('getFieldPrivacy failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pulls the admin-managed option catalogue. Falls back to the built-in
  /// list when the request fails so the screen still works offline.
  Future<void> _loadOptions() async {
    if (_optionsError != null) setState(() => _optionsError = null);
    try {
      final opts = await const ModuleApi().getPrivacyOptions();
      if (!mounted || opts.isEmpty) return;
      setState(() {
        _fields = [
          for (final o in opts) (key: o.fieldKey, labelKey: o.labelKey),
        ];
      });
    } catch (e) {
      // getPrivacyOptions now THROWS instead of returning `const []`. Unguarded
      // that rejection escapes initState as an unhandled async error, so the
      // screen would crash rather than merely mislead — a strictly worse
      // outcome than the bug being fixed here.
      if (!mounted) return;
      setState(() {
        _optionsError = 'Could not refresh the list of fields you can hide.';
      });
      debugPrint('getPrivacyOptions failed: $e');
    }
  }

  Future<void> _loadExtras() async {
    if (_extrasError != null) setState(() => _extrasError = null);
    try {
      final extras = await const ModuleApi().getPrivacyExtras();
      if (!mounted) return;
      setState(() {
        _displayNameMode = (extras['display_name_mode'] ?? 'real').toString();
        _aliasController.text = (extras['alias_name'] ?? '').toString();
        _facebookController.text = (extras['social_facebook'] ?? '').toString();
        _instagramController.text = (extras['social_instagram'] ?? '')
            .toString();
        _telegramController.text = (extras['social_telegram'] ?? '').toString();
      });
    } catch (e) {
      // FAILS CLOSED. This was `catch (_) { /* Keep defaults if the fetch
      // fails. */ }`, and the default is _displayNameMode = 'real'.
      //
      // So a user who had chosen ALIAS, hitting a failed fetch, was shown
      // "use my real name" already selected — and because _saveExtras() posts
      // whatever _displayNameMode currently holds, editing an unrelated
      // social link and tapping Save would have published their real name.
      // A silent, server-side identity disclosure produced by a network
      // error, on the one screen whose entire job is controlling that.
      //
      // The screen now refuses to save until it knows what the user actually
      // chose. Defaults are only safe when being wrong about them is cheap;
      // here being wrong un-anonymises someone.
      if (!mounted) return;
      setState(() => _extrasError = 'Could not load your display-name choice.');
      debugPrint('getPrivacyExtras failed: $e');
    }
  }

  Future<void> _saveExtras() async {
    setState(() => _savingExtras = true);
    try {
      await const ModuleApi().setPrivacyExtras(
        displayNameMode: _displayNameMode,
        aliasName: _aliasController.text.trim(),
        facebook: _facebookController.text.trim(),
        instagram: _instagramController.text.trim(),
        telegram: _telegramController.text.trim(),
      );
      Get.snackbar('Saved'.tr, 'privacy_extras_saved'.tr);
    } catch (e) {
      debugPrint('setPrivacyExtras failed: $e');
      Get.snackbar(
        'Error'.tr,
        failureMessage(e, 'error_privacy_settings_save_failed'),
      );
    } finally {
      if (mounted) setState(() => _savingExtras = false);
    }
  }

  Future<void> _toggle(String key, bool visible) async {
    setState(() {
      if (visible) {
        _hidden.remove(key);
      } else {
        _hidden.add(key);
      }
      _saving = true;
    });
    try {
      await const ModuleApi().setFieldPrivacy(_hidden.toList());
    } catch (_) {
      if (mounted) {
        setState(() {
          // revert
          if (visible) {
            _hidden.add(key);
          } else {
            _hidden.remove(key);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The visible/hidden switches, or the reason they are not being shown.
  ///
  /// Order matters and it is error-before-empty: a failed fetch leaves both
  /// `_hidden` and (in the catalogue's case) the option list empty, so a check
  /// for emptiness placed first would quietly absorb every failure back into
  /// the ordinary-looking screen this change exists to prevent.
  List<Widget> _fieldToggles() {
    // Fail CLOSED. Drawing switches from an unloaded `_hidden` would show
    // every field as "Visible" — a claim about the user's own privacy that we
    // cannot make, and one that `_toggle` would then persist for real on the
    // next tap. No switches until we know what the user actually chose.
    if (_hiddenError != null) {
      return [
        AppErrorState(message: _hiddenError!, onRetry: _reloadFields),
        const SizedBox(height: 12),
      ];
    }

    return [
      // Non-blocking: the fallback catalogue below is still accurate about the
      // user's settings, so the controls stay usable while this explains why
      // the list may be short a recently added field.
      if (_optionsError != null) ...[
        AppErrorState(message: _optionsError!, onRetry: _loadOptions),
        const SizedBox(height: 12),
      ],
      for (final f in _fields)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassPanel(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: !_hidden.contains(f.key),
              onChanged: _saving ? null : (v) => _toggle(f.key, v),
              title: Text(
                f.labelKey.tr,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                _hidden.contains(f.key)
                    ? 'privacy_hidden'.tr
                    : 'privacy_visible'.tr,
              ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Field privacy'.tr,
      subtitle: 'privacy_desc'.tr,
      child: _loading
          ? const Padding(
              // A skeleton shaped like the switch rows it replaces, so the
              // controls fill in rather than pop in over a spinner.
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
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                ..._fieldToggles(),
                const SizedBox(height: 8),
                const SectionLabel(title: 'Display name'),
                const SizedBox(height: 4),
                Text(
                  'display_name_desc'.tr,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppThemeConfig.mutedText(context),
                  ),
                ),
                const SizedBox(height: 12),
                GlassPanel(
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'real',
                        groupValue: _displayNameMode,
                        onChanged: (v) => setState(() => _displayNameMode = v!),
                        title: Text('display_name_real'.tr),
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'alias',
                        groupValue: _displayNameMode,
                        onChanged: (v) => setState(() => _displayNameMode = v!),
                        title: Text('display_name_alias'.tr),
                      ),
                      if (_displayNameMode == 'alias') ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _aliasController,
                          decoration: InputDecoration(
                            labelText: 'Alias / nickname'.tr,
                            hintText: 'alias_name_hint'.tr,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionLabel(title: 'Social media accounts'),
                const SizedBox(height: 4),
                Text(
                  'social_media_desc'.tr,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppThemeConfig.mutedText(context),
                  ),
                ),
                const SizedBox(height: 12),
                GlassPanel(
                  child: Column(
                    children: [
                      TextField(
                        controller: _facebookController,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'Facebook profile'.tr,
                          hintText: 'facebook_hint'.tr,
                          prefixIcon: const Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _instagramController,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'Instagram profile'.tr,
                          hintText: 'instagram_hint'.tr,
                          prefixIcon: const Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _telegramController,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'Telegram profile'.tr,
                          hintText: 'telegram_hint'.tr,
                          prefixIcon: const Icon(Icons.link_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // The extras fetch failed, so what is selected above is this
                // screen's DEFAULT rather than the user's actual choice.
                // Saving would write that default back. Say so, and offer the
                // way out, instead of silently disabling a button.
                if (_extrasError != null) ...[
                  AppErrorState(message: _extrasError!, onRetry: _loadExtras),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    // Blocked while _extrasError is set — see _loadExtras.
                    onPressed: (_savingExtras || _extrasError != null)
                        ? null
                        : _saveExtras,
                    child: _savingExtras
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Save'.tr),
                  ),
                ),
              ],
            ),
    );
  }
}
