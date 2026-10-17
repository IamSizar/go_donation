import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The app's one way to show a snackbar.
///
/// GetX's own default is the TOP of the screen, and on phones with the status
/// bar drawn edge to edge (the Galaxy) the message was painted underneath the
/// clock and icons, unreadable. The bottom is safe on every device, so that is
/// the default here. A call that really wants the top still passes
/// `snackPosition: SnackPosition.TOP`.
SnackbarController appSnackbar(
  String title,
  String message, {
  Duration? duration,
  SnackPosition snackPosition = SnackPosition.BOTTOM,
  EdgeInsets? margin,
  Color? backgroundColor,
  Color? colorText,
  Widget? icon,
  double? borderRadius,
  EdgeInsets? padding,
}) {
  return Get.snackbar(
    title,
    message,
    duration: duration ?? const Duration(seconds: 3),
    snackPosition: snackPosition,
    margin: margin ?? const EdgeInsets.fromLTRB(16, 16, 16, 24),
    backgroundColor: backgroundColor,
    colorText: colorText,
    icon: icon,
    borderRadius: borderRadius ?? 16,
    padding: padding,
  );
}
