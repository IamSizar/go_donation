import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:get/get.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

/// Pick a photo and let the user choose its shape before it is uploaded (#20).
///
/// Every photo field used to take whatever the gallery handed back, so a
/// portrait phone shot became a profile picture the app then had to letterbox
/// or centre-crop on its own, usually through someone's face. The user frames
/// it themselves now.
///
/// The presets are the same everywhere, so a photo means the same shape
/// wherever it appears. [lockRatio] pins it to one for destinations where only
/// that shape makes sense — an avatar is always drawn in a circle, so anything
/// but a square would just be cropped again at display time.
enum PhotoShape {
  /// Avatars, logos, marriage profile photos — anything drawn in a circle or
  /// a square tile.
  square(1, 1, CropAspectRatioPreset.square),

  /// The classic photo shape; what most phone cameras produce.
  standard(4, 3, CropAspectRatioPreset.ratio4x3),

  /// Banners and cover images.
  wide(16, 9, CropAspectRatioPreset.ratio16x9);

  const PhotoShape(this.x, this.y, this.preset);
  final int x;
  final int y;
  final CropAspectRatioPreset preset;
}

/// How much fidelity a picked image may lose on its way to the server (E3).
///
/// The client's rule, in one sentence: compress and resize account images,
/// but leave case documents at their original size and quality "لضمان وضوح
/// تفاصيلها عند الفحص" — so their detail survives inspection.
///
/// The app was doing NEITHER half. No `maxWidth`/`maxHeight` was ever passed,
/// so nothing was resized and an 8000px camera shot went up whole; and every
/// attachment took the avatar path, so a medical report was JPEG-compressed
/// twice (picker at 85, then cropper at 90) on the way. That is the exact
/// inverse of what was asked — the lossy step applied, the cheap one skipped.
enum PhotoFidelity {
  /// Avatars, banners, marriage and personal photos: anything whose job is to
  /// be looked at rather than read. Bounded on the long edge and compressed.
  ///
  /// 1600px is chosen against the display, not the file: it still exceeds the
  /// pixel width of a full-bleed image on a 3x phone, so the bound is
  /// invisible at the sizes these are actually drawn at.
  display(maxDimension: 1600, pickQuality: 85, cropQuality: 90),

  /// ID and identity papers, ration and residence cards, ownership proof,
  /// medical reports, house photos, certificates, CVs — anything a reviewer
  /// has to READ.
  ///
  /// Every knob is null on purpose. `image_picker` documents that a null
  /// `imageQuality` returns the original file untouched, where 100 still
  /// re-encodes it; and a null bound is the only value that resizes nothing.
  document(maxDimension: null, pickQuality: null, cropQuality: null);

  const PhotoFidelity({
    required this.maxDimension,
    required this.pickQuality,
    required this.cropQuality,
  });

  /// Longest edge in pixels, or null to leave the dimensions alone.
  final int? maxDimension;

  /// JPEG quality applied by the picker, or null for the original bytes.
  final int? pickQuality;

  /// JPEG quality applied by the cropper. Null means the crop step is skipped
  /// entirely — a crop always re-encodes, so there is no such thing as a
  /// lossless one.
  final int? cropQuality;

  double? get _maxEdge => maxDimension?.toDouble();
}

/// Which fidelity a registration attachment is filed under, from its rule id.
///
/// The rule id is what the form already carries for each attachment, so this
/// needs no new field threaded through the widget tree.
///
/// UNRECOGNISED RULES ARE DOCUMENTS. Compressing a document destroys detail
/// that cannot be recovered; sending an account image at full size costs some
/// bytes. Only one of those is reversible, so a new attachment nobody
/// remembered to classify falls on the reversible side.
PhotoFidelity fidelityForAttachment(String rule) =>
    _accountImageRules.contains(rule)
    ? PhotoFidelity.display
    : PhotoFidelity.document;

/// The complete list of attachments that are account imagery rather than
/// evidence. Short by design — see the note on [fidelityForAttachment] about
/// which way an omission fails.
const Set<String> _accountImageRules = {
  'recipient_personal_photo',
  'volunteer_personal_photo',
};

/// Opens the gallery (or camera), then the cropper, and returns the path of
/// the cropped file — or null if the user backed out of any step.
///
/// Client note — every upload button (ID card, personal photo, attachments…)
/// only ever opened the gallery: there was no way to take a new picture and
/// have it uploaded on the spot. [source] now defaults to null, which means
/// "ask": [chooseImageSource] puts up a sheet offering the camera or the
/// gallery, and whichever the user taps is what opens. Passing an explicit
/// [source] skips the sheet and opens that one directly — for a caller that
/// only ever wants one of the two (mission check-in's camera-only capture
/// does this itself, without going through here at all).
///
/// [lockRatio] fixes the crop box to one shape and hides the ratio chooser.
/// Leave it null to offer [shapes] plus a free-form option.
///
/// [fidelity] decides whether the image is resized and recompressed at all.
/// A [PhotoFidelity.document] never reaches the cropper: the file the user
/// chose is the file that is uploaded, byte for byte.
Future<String?> pickCroppedImage(
  BuildContext context, {
  ImageSource? source,
  PhotoShape? lockRatio,
  List<PhotoShape> shapes = PhotoShape.values,
  PhotoFidelity fidelity = PhotoFidelity.display,
}) async {
  final chosenSource = source ?? await chooseImageSource(context);
  // Null means the sheet was dismissed without a choice — the same "backed
  // out" outcome as cancelling the picker itself.
  if (chosenSource == null) return null;
  if (!context.mounted) return null;

  XFile? picked;
  try {
    picked = await ImagePicker().pickImage(
      source: chosenSource,
      // Null for a document, which is what makes image_picker hand back the
      // original rather than a re-encoded copy of it.
      maxWidth: fidelity._maxEdge,
      maxHeight: fidelity._maxEdge,
      imageQuality: fidelity.pickQuality,
    );
  } on PlatformException catch (e) {
    // The one failure worth telling the user about by name: the camera (or
    // photo library, on iOS) permission was refused, or revoked in Settings
    // since — tapping the button and having nothing happen would read as a
    // broken control. Every other PlatformException (no camera hardware, the
    // picker already open) is rare enough that the generic message covers it.
    if (context.mounted) {
      final denied =
          e.code == 'camera_access_denied' || e.code == 'photo_access_denied';
      Get.snackbar(
        'Error'.tr,
        (denied ? 'error_photo_access_denied' : 'error_camera_unavailable').tr,
      );
    }
    return null;
  }
  if (picked == null) return null;

  // A document skips the crop. Framing is not worth a second JPEG generation
  // on the one kind of image whose value is in its small print, and "original
  // size" and "cropped" cannot both be true.
  if (fidelity.cropQuality == null) return picked.path;

  // The pick succeeded; if the widget went away before the cropper could open,
  // keep the photo rather than throwing the user's choice away.
  if (!context.mounted) return picked.path;
  return cropImage(
    context,
    path: picked.path,
    lockRatio: lockRatio,
    shapes: shapes,
    fidelity: fidelity,
  );
}

/// The crop half on its own, for callers that already hold a file path.
///
/// Returns null when the user cancels the crop — that cancels the whole pick,
/// rather than silently uploading the uncropped original they just rejected.
/// If the platform cropper is unavailable it returns [path] unchanged: an
/// uncropped photo is a much better outcome than no photo at all.
///
/// [fidelity] bounds the output and sets its compression. A
/// [PhotoFidelity.document] has no business here — the crop itself is the
/// thing it is being protected from — so it is returned unchanged.
Future<String?> cropImage(
  BuildContext context, {
  required String path,
  PhotoShape? lockRatio,
  List<PhotoShape> shapes = PhotoShape.values,
  PhotoFidelity fidelity = PhotoFidelity.display,
}) async {
  final cropQuality = fidelity.cropQuality;
  if (cropQuality == null) return path;

  final dark = Theme.of(context).brightness == Brightness.dark;
  final presets = <CropAspectRatioPresetData>[
    ...shapes.map((s) => s.preset),
    // Free-form last, so the named shapes read as the suggestion.
    if (lockRatio == null) CropAspectRatioPreset.original,
  ];
  try {
    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
      // E3 — the second half of the size constraint. Without these the crop
      // output kept whatever dimensions the source had, so the picker's bound
      // could be undone by the very next step.
      maxWidth: fidelity.maxDimension,
      maxHeight: fidelity.maxDimension,
      compressQuality: cropQuality,
      // A forced ratio is passed here; both uCrop and TOCropViewController
      // hide their ratio row once one is locked.
      aspectRatio: lockRatio == null
          ? null
          : CropAspectRatio(
              ratioX: lockRatio.x.toDouble(),
              ratioY: lockRatio.y.toDouble(),
            ),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop photo'.tr,
          toolbarColor: AppThemeConfig.primary,
          toolbarWidgetColor: Colors.white,
          backgroundColor: dark ? Colors.black : Colors.white,
          activeControlsWidgetColor: AppThemeConfig.primary,
          initAspectRatio: (lockRatio ?? shapes.first).preset,
          lockAspectRatio: lockRatio != null,
          hideBottomControls: lockRatio != null,
          aspectRatioPresets: presets,
        ),
        IOSUiSettings(
          title: 'Crop photo'.tr,
          doneButtonTitle: 'Done'.tr,
          cancelButtonTitle: 'Cancel'.tr,
          aspectRatioLockEnabled: lockRatio != null,
          resetAspectRatioEnabled: lockRatio == null,
          aspectRatioPickerButtonHidden: lockRatio != null,
          aspectRatioPresets: presets,
        ),
      ],
    );
    return cropped?.path;
  } catch (_) {
    return path;
  }
}

/// Puts up a sheet offering the camera or the gallery, and returns whichever
/// the user tapped — or null if they dismissed it without choosing.
///
/// Client note: every upload button in the app only ever opened the gallery.
/// There was no way to take a NEW picture on the spot and have it uploaded —
/// this sheet is the missing choice, shown by [pickCroppedImage] before it
/// asks `image_picker` for anything.
Future<ImageSource?> chooseImageSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => const _ImageSourceSheet(),
  );
}

class _ImageSourceSheet extends StatelessWidget {
  const _ImageSourceSheet();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(AppSpace.md),
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        decoration: BoxDecoration(color: c.card, borderRadius: AppRadius.mdAll),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SourceRow(
              icon: Icons.camera_alt_outlined,
              label: 'photo_source_camera'.tr,
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            Divider(height: 1, color: c.ink.withValues(alpha: 0.08)),
            _SourceRow(
              icon: Icons.photo_library_outlined,
              label: 'photo_source_gallery'.tr,
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppPressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        child: Row(
          children: [
            Icon(icon, color: c.ink),
            const SizedBox(width: AppSpace.md),
            Text(
              label,
              style: TextStyle(fontSize: AppType.body, color: c.ink),
            ),
          ],
        ),
      ),
    );
  }
}
