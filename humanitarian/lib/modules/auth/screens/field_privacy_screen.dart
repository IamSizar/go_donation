import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

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

  // Privacy Settings spec — display-name choice + social links.
  String _displayNameMode = 'real';
  final _aliasController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _telegramController = TextEditingController();
  bool _savingExtras = false;

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

  Future<void> _load() async {
    try {
      final hidden = await const ModuleApi().getFieldPrivacy();
      if (mounted) setState(() => _hidden.addAll(hidden));
    } catch (_) {
      // Keep everything visible if the fetch fails.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pulls the admin-managed option catalogue. Falls back to the built-in
  /// list when the request fails so the screen still works offline.
  Future<void> _loadOptions() async {
    final opts = await const ModuleApi().getPrivacyOptions();
    if (!mounted || opts.isEmpty) return;
    setState(() {
      _fields = [for (final o in opts) (key: o.fieldKey, labelKey: o.labelKey)];
    });
  }

  Future<void> _loadExtras() async {
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
    } catch (_) {
      // Keep defaults if the fetch fails.
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
      Get.snackbar('Error'.tr, e.toString());
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

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Field privacy'.tr,
      subtitle: 'privacy_desc'.tr,
      child: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _savingExtras ? null : _saveExtras,
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
