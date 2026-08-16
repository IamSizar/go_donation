// Resolving a stored upload path into a URL the app can load.
//
// WHY THIS FILE EXISTS (K13)
// `partners.logo_path` (migration 035) and `app_content.logo_path` (migration
// 112) are the SAME kind of value — a path into the same upload store — and
// migration 112 says so in as many words. The resolver for it already existed
// as `partnerLogoUrl` inside partners_screen.dart, which is a screen file: the
// Contact page cannot reach it without importing a whole screen to get at a
// six-line helper, and copying it would leave two answers to one question.
//
// This is the same move the social-links parser made for exactly the same
// reason (K17, shared/utils/social_links.dart): shared code is earned when the
// second feature needs it, and this is that moment.
import 'package:flutter_application_1/api/links.dart';

/// Turns a stored upload path into a loadable URL, or null when there is none.
///
/// An absolute URL is returned unchanged — some rows hold one, written by an
/// older admin build. Anything else is resolved against [publicBaseUrl], with
/// leading slashes stripped so a stored "/uploads/x.png" does not resolve away
/// the project folder in the base URL.
///
/// Null rather than an empty string, so a caller renders no image at all rather
/// than an image widget pointed at nothing.
String? uploadedImageUrl(dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return null;
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) return path;
  return Uri.parse(
    publicBaseUrl,
  ).resolve(path.replaceFirst(RegExp(r'^/+'), '')).toString();
}
