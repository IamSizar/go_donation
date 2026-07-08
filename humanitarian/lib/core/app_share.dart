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

/// Share the app itself (a localized pitch + the app link).
Future<void> shareApp() async {
  await Share.share(withAppLink('share_app_text'.tr));
}
