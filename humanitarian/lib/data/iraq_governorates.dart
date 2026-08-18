/// Iraq's 18 governorates, for the grantor registration form's governorate
/// dropdown. Each entry's translation key is the English name itself — add
/// the Arabic/Kurdish translations to app_translations.dart under the same
/// key to localize the dropdown.
const List<String> iraqGovernorates = [
  'Baghdad',
  'Basra',
  'Nineveh',
  'Erbil',
  'Sulaymaniyah',
  'Duhok',
  'Kirkuk',
  'Anbar',
  'Najaf',
  'Karbala',
  'Wasit',
  'Babil',
  'Diyala',
  'Salah al-Din',
  'Dhi Qar',
  'Maysan',
  'Muthanna',
  'Al-Qadisiyyah',
];

/// Resolves a stored city string to its governorate KEY, case- and
/// whitespace-insensitively, or '' when it is not one of the eighteen.
///
/// WHY THIS EXISTS
/// The keys are capitalised — 'Duhok' — because they are also the English
/// labels. But `city` is a free-text field on several forms, prefilled from a
/// `city_user` preference that itself came from typing, so what is actually
/// stored is whatever the volunteer wrote: `duhok`, `Duhok `, `DUHOK`. A card
/// then called `.tr` on that and got the string back unchanged, so an Arabic
/// screen read "duhok" beside «تم الإرسال» and «أربيل».
///
/// Matching case-insensitively against a CLOSED list of eighteen names is a
/// normalisation, not a guess: either the text is one of them or it is not,
/// and anything else — a village, a district, a typo — returns '' and is left
/// exactly as the person wrote it. That distinction is the whole point; a
/// looser match would start rewriting people's own words.
String? governorateKeyFor(String? city) {
  final value = (city ?? '').trim();
  if (value.isEmpty) return null;
  for (final name in iraqGovernorates) {
    if (name.toLowerCase() == value.toLowerCase()) return name;
  }
  return null;
}
