// Reading and opening the free-text `social_links` column.
//
// WHY THIS FILE EXISTS (K17)
// Two tables store social links the same way — `partners.social_links`
// (migration 035, "one URL per line") and `city_directory_entries.social_links`
// (migration 100, whose own comment says it exists to "match
// partners.social_links, which already holds the same kind of value").
//
// Only one of the two screens could read it. The partner page parsed the
// column and rendered tappable chips; the City Guide place page printed the
// whole raw string into a read-only detail line, so on a screen where the
// phone dials, the email opens mail and the website opens a browser, the
// social links were the one contact method that did nothing.
//
// The parser lives here rather than in either screen because both features now
// need it — the project's rule for when shared code is earned. Two private
// copies of "split on newlines and commas" would drift the first time someone
// pasted a semicolon-separated list into one of them.

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

/// Splits the stored value into individual links.
///
/// Both separators are real. Migration 035 documents one URL per line, and the
/// admin form lets staff comma-separate them, so the column contains both in
/// production. Empty fragments — what a trailing comma or a half-finished
/// paste leaves behind — are dropped rather than becoming a chip that opens
/// nothing.
List<String> socialLinksFrom(dynamic raw) {
  final text = (raw ?? '').toString();
  if (text.trim().isEmpty) return const [];
  return text
      .split(RegExp(r'[\n,]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Names the network behind [url], so a chip reads "Facebook" rather than
/// carrying a raw address the user has to parse themselves.
///
/// Falls back to a generic word for a host we do not know: still a label, and
/// still better than printing the URL, which is what the inert version did.
String socialNetworkLabel(String url) {
  final u = url.toLowerCase();
  if (u.contains('facebook') || u.contains('fb.')) return 'Facebook';
  if (u.contains('instagram') || u.contains('instagr.am')) return 'Instagram';
  if (u.contains('wa.me') || u.contains('whatsapp')) return 'WhatsApp';
  if (u.contains('t.me') || u.contains('telegram')) return 'Telegram';
  if (u.contains('youtube') || u.contains('youtu.be')) return 'YouTube';
  if (u.contains('tiktok')) return 'TikTok';
  if (u.contains('twitter') || u.contains('x.com')) return 'X';
  if (u.contains('linkedin')) return 'LinkedIn';
  // Only the fallback is translated. The names above are proper nouns and stay
  // as they are in every language; running them through .tr would invite a
  // 'Facebook' key later and "translate" a brand, which is how one screen ends
  // up saying «فيسبوك» while another says «Facebook».
  return 'Social'.tr;
}

/// Opens [url] in the platform's browser or the network's own app.
///
/// Staff type these by hand, so a bare `facebook.com/place` with no scheme is
/// the common case; without the prefix `Uri.parse` produces a relative URI and
/// the launch silently does nothing.
///
/// Failures are logged rather than shown. A social link is a secondary
/// affordance next to the phone number and the map, and a dialog over a place
/// page because one chip could not open is louder than the problem — but
/// swallowing it in silence is how the inert version stayed unnoticed, so it
/// leaves a trace.
Future<void> openSocialLink(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;
  final normalized = trimmed.startsWith(RegExp(r'https?://'))
      ? trimmed
      : 'https://$trimmed';
  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    debugPrint('openSocialLink: unparseable link $url');
    return;
  }
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('openSocialLink: could not open $normalized: $e');
  }
}
