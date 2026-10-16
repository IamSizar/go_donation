import 'package:flutter/services.dart';

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

/// R2 #26 — the longest national number (digits after the dial code) per
/// country. Unknown countries get what E.164 leaves after the dial code.
const Map<String, int> _nationalDigits = {
  '964': 10, // Iraq — 7XX XXX XXXX
  '1': 10,
  '20': 10,
  '33': 9,
  '44': 10,
  '46': 9,
  '49': 11,
  '90': 10,
  '961': 8,
  '962': 9,
  '963': 9,
  '965': 8,
  '966': 9,
  '968': 8,
  '971': 9,
  '973': 8,
  '974': 8,
  '98': 10,
};

int maxNationalDigits(String dialCode) {
  final code = dialCode.replaceAll(RegExp(r'\D'), '');
  return _nationalDigits[code] ?? (15 - code.length);
}

/// R2 #26 — keeps the phone field to the selected country's rules as the
/// user types: digits only, a leading trunk 0 is dropped (in Iraq "0770…"
/// becomes "770…" so no one types 11 digits), and nothing past the
/// country's length is accepted. [dialCode] is read on every keystroke, so
/// switching the country picker applies the new rule at once.
class NationalNumberInputFormatter extends TextInputFormatter {
  NationalNumberInputFormatter(this.dialCode);

  final String Function() dialCode;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    final max = maxNationalDigits(dialCode());
    if (digits.length > max) digits = digits.substring(0, max);
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
