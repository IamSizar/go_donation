// Formatting money for display.
//
// WHY THIS FILE EXISTS
// Two problems, one cause.
//
// 1. The currency code was printed raw, so an Arabic reader saw «IQD 0» on a
//    screen where every other word was Arabic. A translation for IQD has
//    existed all along — د.ع in Arabic, and Kurdish in both dialects — and
//    nothing called it.
//
// 2. _formatMoney was copied byte-for-byte into four screens (payment methods,
//    marketplace section, marketplace orders, cart). Fixing the leak in one
//    would have left the other three wrong, which is how the app came to
//    render money two different ways in the first place.
//
// So the formatting lives here once, and the screens call it.
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// The currency code as the reader should see it: «د.ع» rather than «IQD».
///
/// An unknown code comes back unchanged, which is the behaviour we want rather
/// than a bug to work around: GetX returns the key when there is no
/// translation, and for a currency the code itself IS the sensible fallback.
/// A campaign priced in USD stays "USD" instead of becoming a guess.
String localizedCurrency(String code) {
  final trimmed = code.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.tr;
}

/// An amount with its currency, grouped and localised for the reader.
///
/// The number is grouped by the reader's locale (NumberFormat), and the code is
/// translated. Pass the currency the record actually carries; [fallbackCode] is
/// used only when the record has none, which is the common case for rows
/// written before the currency column existed.
String formatMoney(
  num amount,
  String currency, {
  String fallbackCode = 'IQD',
}) {
  final locale = Get.locale?.toLanguageTag() ?? 'en';
  final formatter = NumberFormat.decimalPattern(locale);
  final code = currency.trim().isEmpty ? fallbackCode : currency.trim();
  return '${formatter.format(amount)} ${localizedCurrency(code)}';
}
