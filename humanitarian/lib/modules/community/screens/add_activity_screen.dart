import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:flutter_application_1/modules/community/controllers/community_controller.dart';
import 'package:flutter_application_1/shared/utils/image_pick.dart';
import 'package:get/get.dart';

/// OPOS #25280 — the translation key for a failed submission's snackbar.
///
/// A top-level function (not inlined in the catch block) so it can be pinned
/// directly with synthetic exceptions, the same way `isOfflineFailure` itself
/// is tested — no widget pump or real timer needed.
///
/// [isOfflineFailure] covers exactly the class of error where the request may
/// have reached the server anyway: ModuleApi's 12s request timeout does not
/// cancel the underlying HTTP call (Dart's Future.timeout only stops
/// AWAITING it), so a slow-but-alive server can still insert the row after
/// the app has already given up. For that class we say we couldn't CONFIRM
/// success, never that it failed. A genuine server rejection (validation, DB
/// error -- postJson's plain Exception) still gets the definite failure
/// message.
String activitySubmitFailureKey(Object error) => isOfflineFailure(error)
    ? 'activity_submit_unconfirmed'
    : 'activity_submit_failed';

/// #30 — "Add an Activity": an app user suggests a new City Guide place. It is
/// submitted with status='pending' and appears in the admin approval queue
/// before it shows publicly.
class AddActivityScreen extends StatefulWidget {
  const AddActivityScreen({super.key});

  @override
  State<AddActivityScreen> createState() => _AddActivityScreenState();
}

class _AddActivityScreenState extends State<AddActivityScreen> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _hours = TextEditingController();
  final _selected = <String>{};

  /// R2 #62 — the place's position, taken from the phone's GPS with one tap.
  /// It replaces two boxes asking the user to type a latitude and a longitude,
  /// which nobody knows by heart. Null until the user taps «تحديد موقعي».
  Position? _position;
  bool _locating = false;
  String? _locationError;

  /// R2 #62 — local paths of the photos the user picked. They are uploaded only
  /// when the form is submitted, so an abandoned form uploads nothing.
  final _photos = <String>[];
  static const _maxPhotos = 6;

  /// The chosen sub-category's slug (K16). Null until one is picked, which is
  /// what `_submit` validates — the field is required, exactly as the free-text
  /// box it replaces was.
  String? _categorySlug;

  bool _busy = false;

  late final CommunityController _controller =
      Get.isRegistered<CommunityController>()
      ? Get.find<CommunityController>()
      : Get.put(CommunityController());

  @override
  void initState() {
    super.initState();
    if (_controller.sectors.isEmpty) _controller.fetchSectors();
    // K16 — the curated sub-categories. Without them "التصنيف" was a free-text
    // box, which is how the column ended up holding 'asdsa' and single Arabic
    // letters alongside real values.
    if (_controller.categories.isEmpty) _controller.fetchCategories();
  }

  @override
  void dispose() {
    for (final c in [_name, _city, _address, _phone, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The sub-categories offered, given the sectors ticked below.
  ///
  /// Scoped rather than showing all 27: a place tagged "الصحة" has no business
  /// offering "Malls and shopping complexes", and the whole point of the
  /// curated list is that the pair is coherent. With no sector chosen yet the
  /// list is empty and the field says so, which is also the nudge to pick one.
  List<Map<String, dynamic>> get _categoryOptions {
    if (_selected.isEmpty) return const [];
    return _controller.categories
        .where((c) => _selected.contains((c['sector_slug'] ?? '').toString()))
        .toList();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _categorySlug == null) {
      Get.snackbar('add_activity'.tr, 'activity_need_fields'.tr);
      return;
    }
    setState(() => _busy = true);
    try {
      // Photos first: the submission carries the paths the server issued. If
      // one upload fails the whole submit stops, so the user is never told a
      // place was suggested without the photos they added.
      final gallery = <String>[];
      for (final path in _photos) {
        gallery.add(await const ModuleApi().uploadPhoto(File(path)));
      }
      await const ModuleApi().submitCommunity({
        'name': _name.text.trim(),
        // The SLUG, not a typed name: it is stable across languages, and the
        // City Guide filter matches it directly.
        'category': _categorySlug!,
        'city': _city.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'opening_hours': _hours.text.trim(),
        'latitude': _position?.latitude.toStringAsFixed(7) ?? '',
        'longitude': _position?.longitude.toStringAsFixed(7) ?? '',
        'sectors': _selected.toList(),
        'gallery': gallery,
      });
      if (!mounted) return;
      Get.back();
      Get.snackbar('add_activity'.tr, 'activity_submitted'.tr);
    } catch (e) {
      debugPrint('add activity submit failed: $e');
      if (mounted) {
        Get.snackbar('add_activity'.tr, activitySubmitFailureKey(e).tr);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Takes the phone's current position. Every failure is reported in words:
  /// a location button that silently does nothing reads as a broken one.
  Future<void> _useMyLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      // Service check first: with location off at the OS level the permission
      // prompt never appears and the request just hangs.
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _locationError = 'location_services_disabled'.tr);
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _locationError = 'location_permission_required'.tr);
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (mounted) setState(() => _position = position);
    } catch (e) {
      debugPrint('[add-activity] location failed: $e');
      if (mounted) setState(() => _locationError = 'location_failed'.tr);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    // A place is looked at, so these are display photos: resized and
    // compressed, with the usual camera-or-gallery choice.
    final picked = await pickCroppedImage(context);
    if (picked != null && mounted) setState(() => _photos.add(picked));
  }

  Widget _locationRow(BuildContext context) {
    final set = _position != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _locating ? null : _useMyLocation,
            icon: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    set
                        ? Icons.check_circle_rounded
                        : Icons.my_location_rounded,
                  ),
            label: Text(
              set ? 'activity_location_set'.tr : 'activity_use_my_location'.tr,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppThemeConfig.text(context),
              side: BorderSide(color: AppThemeConfig.border(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (set)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => setState(() => _position = null),
                child: Text('activity_remove_location'.tr),
              ),
            ),
          if (_locationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _locationError!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _photoStrip(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'activity_photos'.tr,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppThemeConfig.text(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _photos.length; i++)
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(_photos[i]), fit: BoxFit.cover),
                      ),
                      PositionedDirectional(
                        top: 2,
                        end: 2,
                        child: GestureDetector(
                          onTap: () => setState(() => _photos.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_photos.length < _maxPhotos)
                InkWell(
                  onTap: _addPhoto,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: AppThemeConfig.softSurface(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppThemeConfig.border(context)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_rounded,
                          color: AppThemeConfig.mutedText(context),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'activity_add_photo'.tr,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppThemeConfig.mutedText(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      title: 'add_activity'.tr,
      subtitle: 'activity_subtitle'.tr,
      // The page itself carries no side gutter (the list supplies it), and the
      // submit button is pinned below the list. It used to be the last item
      // IN the list, which left it under the phone's navigation buttons.
      padded: false,
      bottomBar: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'activity_submitting'.tr : 'activity_submit'.tr),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          _field(_name, 'activity_name'.tr, required: true),
          _field(_city, 'activity_city'.tr),
          _field(_address, 'activity_address'.tr),
          _field(_phone, 'activity_phone'.tr, keyboard: TextInputType.phone),
          _field(_hours, 'city_opening_hours'.tr),
          _locationRow(context),
          _photoStrip(context),
          const SizedBox(height: 8),
          Obx(() {
            final sectors = _controller.sectors.toList();
            if (sectors.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'field_sectors'.tr,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in sectors)
                      _sectorChip(
                        (s['slug'] ?? '').toString(),
                        localizedContentFromValues(
                          base: (s['name_en'] ?? '').toString(),
                          arabic: (s['name_ar'] ?? '').toString(),
                          sorani: (s['name_ckb'] ?? '').toString(),
                          badini: (s['name_kmr'] ?? '').toString(),
                          fallback: (s['slug'] ?? '').toString(),
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),
          const SizedBox(height: 16),
          // K16 — "التصنيف" is a picker now, fed by the curated list under the
          // sectors ticked above. It sits BELOW the sectors on purpose: it
          // cannot offer anything until one is chosen, and a control that
          // fills in after the control above it reads as a consequence rather
          // than as a bug.
          Obx(() {
            final options = _categoryOptions;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'activity_category'.tr} *',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 8),
                if (_controller.categoriesLoading.value)
                  const AppSkeleton(child: SizedBox(height: 38))
                else if (_controller.categoriesError.value != null)
                  AppErrorState(
                    message: _controller.categoriesError.value!,
                    onRetry: _controller.fetchCategories,
                  )
                else if (options.isEmpty)
                  Text(
                    'activity_pick_sector_first'.tr,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in options)
                        _categoryChip(
                          (c['slug'] ?? '').toString(),
                          localizedContentFromValues(
                            base: (c['name_en'] ?? '').toString(),
                            arabic: (c['name_ar'] ?? '').toString(),
                            sorani: (c['name_ckb'] ?? '').toString(),
                            badini: (c['name_kmr'] ?? '').toString(),
                            fallback: (c['slug'] ?? '').toString(),
                          ),
                        ),
                    ],
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        // Explicit theme-aware text colour — without this the input text
        // inherited the dark-theme default (white) and was invisible in light
        // mode.
        style: TextStyle(color: AppThemeConfig.text(context)),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          labelStyle: TextStyle(color: AppThemeConfig.mutedText(context)),
          filled: true,
          fillColor: AppThemeConfig.softSurface(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppThemeConfig.border(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppThemeConfig.border(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppThemeConfig.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _sectorChip(String slug, String label) {
    final active = _selected.contains(slug);
    return FilterChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => setState(() {
        if (active) {
          _selected.remove(slug);
        } else {
          _selected.add(slug);
        }
        // Un-ticking a sector can strand a sub-category belonging to it, which
        // would then be submitted under a sector the place is not in.
        if (_categorySlug != null &&
            !_categoryOptions.any(
              (c) => (c['slug'] ?? '').toString() == _categorySlug,
            )) {
          _categorySlug = null;
        }
      }),
    );
  }

  /// One sub-category option. Single-select: a place has one classification,
  /// and the spec calls the field "التصنيف الرئيسي والفرعي" — one of each.
  Widget _categoryChip(String slug, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _categorySlug == slug,
      onSelected: (picked) =>
          setState(() => _categorySlug = picked ? slug : null),
    );
  }
}
