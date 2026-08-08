import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';

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

/// Opens the gallery (or camera), then the cropper, and returns the path of
/// the cropped file — or null if the user backed out of either step.
///
/// [lockRatio] fixes the crop box to one shape and hides the ratio chooser.
/// Leave it null to offer [shapes] plus a free-form option.
Future<String?> pickCroppedImage(
  BuildContext context, {
  ImageSource source = ImageSource.gallery,
  PhotoShape? lockRatio,
  List<PhotoShape> shapes = PhotoShape.values,
  int imageQuality = 85,
}) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    imageQuality: imageQuality,
  );
  if (picked == null) return null;
  // The pick succeeded; if the widget went away before the cropper could open,
  // keep the photo rather than throwing the user's choice away.
  if (!context.mounted) return picked.path;
  return cropImage(
    context,
    path: picked.path,
    lockRatio: lockRatio,
    shapes: shapes,
  );
}

/// The crop half on its own, for callers that already hold a file path.
///
/// Returns null when the user cancels the crop — that cancels the whole pick,
/// rather than silently uploading the uncropped original they just rejected.
/// If the platform cropper is unavailable it returns [path] unchanged: an
/// uncropped photo is a much better outcome than no photo at all.
Future<String?> cropImage(
  BuildContext context, {
  required String path,
  PhotoShape? lockRatio,
  List<PhotoShape> shapes = PhotoShape.values,
}) async {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final presets = <CropAspectRatioPresetData>[
    ...shapes.map((s) => s.preset),
    // Free-form last, so the named shapes read as the suggestion.
    if (lockRatio == null) CropAspectRatioPreset.original,
  ];
  try {
    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
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
