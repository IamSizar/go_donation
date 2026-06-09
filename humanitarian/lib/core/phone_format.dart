import 'package:flutter/services.dart';

/// Phone display/formatting helpers. The DB stores one canonical form
/// ("07508582031"); the UI shows it grouped with spaces ("0750 858 2031").

/// Format any stored/typed phone for display: "07508582031" / "9647508582031"
/// / "7508582031" → "0750 858 2031". Falls back to the trimmed input when it
/// can't reduce to a 10-digit national number.
String formatPhoneForDisplay(String? raw) {
  if (raw == null) return '';
  var d = raw.replaceAll(RegExp(r'\D'), '');
  d = d.replaceFirst(RegExp(r'^(00)?964'), '');
  d = d.replaceFirst(RegExp(r'^0+'), '');
  if (d.length != 10) return raw.trim();
  return '0${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
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
