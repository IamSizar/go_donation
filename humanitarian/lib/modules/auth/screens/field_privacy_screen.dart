import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
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
  static const _fields = <({String key, String labelKey})>[
    (key: 'full_name', labelKey: 'pf_full_name'),
    (key: 'phone', labelKey: 'pf_phone'),
    (key: 'gender', labelKey: 'pf_gender'),
    (key: 'address', labelKey: 'pf_address'),
    (key: 'date_of_birth', labelKey: 'pf_dob'),
    (key: 'profile_picture', labelKey: 'pf_picture'),
  ];

  final _hidden = <String>{};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
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
          ? const Center(child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ))
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
              ],
            ),
    );
  }
}
