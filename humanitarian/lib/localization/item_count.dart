// Counting things in a language that does not count like English.
//
// WHY THIS FILE EXISTS
// The cart bar printed `'$totalQuantity ${'items'.tr}'` — a number glued to one
// fixed noun. With one product in the cart that reads "1 items" in English and
// "١ عناصر" in Arabic, which is worse: عناصر is the 3–10 plural, so Arabic gets
// a form that is not merely unpolished but ungrammatical for the commonest
// case of all.
//
// Arabic marks number in four shapes where English has two:
//   1        عنصر     singular
//   2        عنصران   dual — a form English does not have at all
//   3–10     عناصر    "few" plural, which is what was hardcoded
//   11+      عنصرًا    singular again, accusative
//
// So this cannot be a `count == 1 ? a : b` at the call site; the rule belongs
// to the locale, not to the widget.
//
// KURDISH FALLS BACK, IT DOES NOT GUESS
// Sorani and Badini have an `items` entry and no count-specific ones. Adding
// them would mean inventing Kurdish, which this project forbids. `_form` asks
// GetX for a key and checks whether it came back translated — GetX returns the
// key itself on a miss — so a locale that has not spelled its forms out simply
// keeps the single word it always used. That is the same graceful degradation
// locale_routing_test already pins for Kurdish generally.
import 'package:get/get.dart';

/// Returns [key]'s translation, or null when this locale has no entry.
///
/// GetX signals a miss by echoing the key back, which is the behaviour that
/// makes a missing translation render as `items_one` on screen. Here it is the
/// signal to fall back rather than a bug.
String? _form(String key) {
  final value = key.tr;
  return value == key ? null : value;
}

/// The word for "items" that agrees with [count] in the current locale.
///
/// Falls back to the uncounted `items` for any locale that has not declared
/// the count-specific forms.
String itemCountNoun(int count) {
  final n = count.abs();
  final String? specific;
  if (n == 1) {
    specific = _form('items_one');
  } else if (n == 2) {
    specific = _form('items_two');
  } else if (n >= 3 && n <= 10) {
    specific = _form('items_few');
  } else {
    specific = _form('items_many');
  }
  return specific ?? 'items'.tr;
}

/// "3 عناصر" / "1 item" — the count and its agreeing noun.
///
/// The number keeps Latin digits deliberately: the rest of this app prints
/// prices and quantities the same way, and mixing ٣ into a screen that shows
/// IQD 15,000 beside it would be the inconsistency, not the fix.
String itemCountLabel(int count) => '$count ${itemCountNoun(count)}';
