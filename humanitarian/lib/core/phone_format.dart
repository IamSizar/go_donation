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
