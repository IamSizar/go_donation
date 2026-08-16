import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

/// #49 — sharing helpers built on share_plus. Shares open the OS share sheet so
/// the user can pick WhatsApp, Telegram, Email, etc. The app link is appended
/// only when [appShareUrl] is configured, so no broken link is ever shared.

/// Append the configured app link to [text] (when set).
String withAppLink(String text) {
  final link = appShareUrl.trim();
  return link.isEmpty ? text : '$text\n\n$link';
}

/// The rect the share sheet is anchored to, in the source view's coordinates.
///
/// WHY THIS IS NOT OPTIONAL. iOS presents the share sheet as a popover pinned
/// to a rect inside the presenting view, and it rejects an empty one. share_plus
/// sends `originX/originY/originWidth/originHeight` only when the caller passes
/// `sharePositionOrigin`; leave it null and those four keys are absent, the iOS
/// side reads {{0, 0}, {0, 0}}, and the platform throws:
///
///     PlatformException(error, sharePositionOrigin: argument must be set,
///     {{0, 0}, {0, 0}} must be non-zero and within coordinate space of source
///     view: {{0, 0}, {402, 874}})
///
/// Nothing awaited that Future at the tap sites, so the throw surfaced nowhere
/// and "مشاركة التطبيق" simply looked like a control that did nothing.
///
/// Pass the tapped widget's [context] where there is one: the popover then
/// points at the row the user actually touched, which is visible on iPad where
/// the popover draws an arrow. When [context] is null, or its element is not
/// laid out yet, fall back to a small rect at the centre of the window — iOS
/// checks only that the rect is non-empty and inside the source view, and the
/// centre satisfies both.
Rect shareAnchor(BuildContext? context) {
  // `mounted` is checked first because findRenderObject() ASSERTS on an
  // inactive element rather than returning null. Sharing after an await gap is
  // a real shape in this codebase (the news card awaits requireSignIn before
  // acting), so an unmounted context is reachable, not hypothetical.
  final render = (context != null && context.mounted)
      ? context.findRenderObject()
      : null;
  if (render is RenderBox && render.hasSize && !render.size.isEmpty) {
    return render.localToGlobal(Offset.zero) & render.size;
  }

  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  // A degenerate window (headless) would otherwise produce a rect straddling
  // the origin, which is empty AND outside the view — both things iOS checks.
  if (size.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);

  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
}

/// Share the app itself (a localized pitch + the app link).
///
/// [context] is the tapped widget's context, used to anchor the sheet — see
/// [shareAnchor]. It stays optional so a bare `onTap: shareApp` still compiles.
Future<void> shareApp([BuildContext? context]) async {
  await Share.share(
    withAppLink('share_app_text'.tr),
    sharePositionOrigin: shareAnchor(context),
  );
}
