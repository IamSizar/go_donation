import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Phone display/formatting helpers. The DB stores one canonical form
/// (`<dial code><national number>`, e.g. "9647508582031"); the UI shows
/// Iraqi numbers grouped in their familiar local form ("0750 858 2031") and
/// any other country's number as `+<dial code><number>`.

/// #39 — international phone support: format any stored/typed phone for
/// display. Iraqi numbers (new "964..." canonical, the old "0..." canonical,
/// or a bare "750...") render as "0750 858 2031"; any other country renders
/// as `+<digits>` since there's no client-side per-country grouping table.
/// Falls back to the trimmed input when it isn't a recognizable digit string.
String formatPhoneForDisplay(String? raw) {
  if (raw == null) return '';
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return raw.trim();

  var national = digits.replaceFirst(RegExp(r'^(00)?964'), '');
  national = national.replaceFirst(RegExp(r'^0+'), '');
  if (national.length == 10) {
    return '0${national.substring(0, 3)} ${national.substring(3, 6)} ${national.substring(6)}';
  }

  return '+$digits';
}

/// The app's single phone-number rule: returns a localized message describing
/// what is wrong with [value], or null when it is acceptable.
///
/// This lived privately inside login.dart's State, which is why the
/// registration form's profile phone1 / phone2 fields shipped with no
/// validation at all — there was nothing to reuse. It is here so the sign-in
/// screen and the registration form apply the same rule, and so the rule can
/// be tested directly (test/core/phone_validation_test.dart).
///
/// [dialCode] is the country's dial code without "+", e.g. "964". Fields with
/// no country picker pass "964": the backend assumes Iraq for a bare local
/// number (auth.NormalizePhone), so the form must judge it the same way.
///
/// [required] false allows a blank value — the registration profile's two
/// phone fields sit behind the admin's per-field rules and are commonly left
/// out, and a blank optional field is not a malformed number.
///
/// The client validates for UX; the server is the authority. Where the two
/// differ, this must be the STRICTER of the two, so the form never accepts
/// something the server will then refuse.
String? phoneValidationMessage(
  String? value, {
  required String dialCode,
  bool required = true,
}) {
  if (value == null || value.trim().isEmpty) {
    return required ? 'Please enter your phone number'.tr : null;
  }
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (dialCode == '964') {
    // Iraq keeps its precise NSN-length check: 10 digits, or 11 with a
    // leading trunk 0. This mirrors auth.NormalizePhone's Iraq branch exactly
    // — a 9-digit Iraqi number passed the generic range once and reached an
    // "accepted" registration (OPOS #25268).
    if (digits.length == 10) return null;
    if (digits.length == 11 && digits.startsWith('0')) return null;
    return 'Enter 10 digits (or 11 starting with 0)'.tr;
  }
  // Other countries: a generic sanity range; the backend applies the
  // authoritative E.164 check. The floor is 7, not 4, because the server
  // requires 7-15 digits total (backend/internal/auth/phone.go) — a 4-digit
  // number used to pass here and be refused there.
  if (digits.length >= 7 && digits.length <= 14) return null;
  return 'Enter a valid phone number'.tr;
}

/// Live input formatter that groups digits with spaces as the user types:
/// "750 858 2031" (10 digits) or "0750 858 2031" (with a leading 0). The
/// backend normalizes regardless, so the grouping is purely cosmetic.
class PhoneSpaceInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    // 4-3-4 when a leading 0 is present, otherwise 3-3-4.
    final sizes = digits.startsWith('0') ? <int>[4, 3, 4] : <int>[3, 3, 4];
    final sb = StringBuffer();
    var i = 0;
    for (final s in sizes) {
      if (i >= digits.length) break;
      if (sb.isNotEmpty) sb.write(' ');
      final end = (i + s) > digits.length ? digits.length : (i + s);
      sb.write(digits.substring(i, end));
      i = end;
    }
    if (i < digits.length) {
      sb.write(' ');
      sb.write(digits.substring(i));
    }
    final text = sb.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
