// Turning a typed-in contact detail into a link that actually opens.
//
// WHY THIS FILE EXISTS (K13)
// Migration 112 gave each Contact page a phone number, a WhatsApp line and an
// email address, and the server validates them LOOSELY on purpose: a public
// line is legitimately "(0750) 858-2031 ext. 12", so `ValidateContact` counts
// digits rather than banning punctuation.
//
// That loose value cannot be handed to a URI as-is. `Uri.tryParse('tel:(0750)
// 858-2031')` returns null for the brackets and spaces, and the app's existing
// launchers return in silence when parsing fails — so the Contact page would
// have rendered a phone button that dials nothing. Which is the exact failure
// this project already shipped once, on the City Guide's social links (K17),
// and the reason those got a shared parser instead of a second private copy.
//
// So each builder here returns a Uri or NULL, and null means "do not offer this
// as an action at all". The value is still shown to the reader as text; what it
// does not become is a control that quietly does nothing.
//
// These are pure functions with no widget in sight so the rule can be read and
// tested on its own — the parsing is the part worth being sure about.
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// The `tel:` URI for a phone number a human typed, or null if it holds no
/// number to dial.
///
/// Digits are extracted and a LEADING `+` is preserved, because it is the
/// difference between an international number and a local one — everything
/// else a person writes around a phone number (spaces, brackets, dashes, the
/// word "ext.") is presentation and would break the URI.
Uri? contactDialUri(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final isInternational = trimmed.startsWith('+');
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  // "call us any time" is prose, not a number. Offering it as a dial button
  // would be a button that fails the moment it is pressed.
  if (digits.isEmpty) return null;
  return Uri(scheme: 'tel', path: isInternational ? '+$digits' : digits);
}

/// The `wa.me` URI for a WhatsApp line, or null if it holds no number.
///
/// wa.me takes DIGITS ONLY — no `+`, no spaces — which is why this cannot
/// share [contactDialUri]'s output. Same rule as the technical-support screen,
/// which has opened WhatsApp this way since it shipped.
Uri? contactWhatsAppUri(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return Uri.parse('https://wa.me/$digits');
}

/// The `mailto:` URI for an email address, or null if the value is not one.
///
/// The shape check mirrors the server's `ValidateContact` (one `@`, a dot in
/// the domain) rather than attempting real RFC validation: the point is only to
/// refuse a value no mail app could act on, and the server is the copy that
/// protects the data.
Uri? contactEmailUri(String raw) {
  final trimmed = raw.trim();
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed)) return null;
  // Case is preserved: the local part of an address is case-sensitive by spec,
  // and lower-casing somebody else's address is not this screen's decision.
  return Uri(scheme: 'mailto', path: trimmed);
}

/// Opens a contact link in the platform's dialer, mail client or browser.
///
/// A failure is logged rather than shown. By the time this is called the URI
/// has already been proved well-formed by one of the builders above, so what
/// remains is "this device has no app for tel:" — a dialog about that is louder
/// than the problem, but silence is how the inert version stayed unnoticed, so
/// it leaves a trace.
Future<void> openContactLink(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('openContactLink: could not open $uri: $e');
  }
}
