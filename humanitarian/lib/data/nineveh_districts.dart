/// Volunteer/Employee registration spec — "Housing Information": when the
/// governorate is Nineveh, a District dropdown opens before the side/
/// neighborhood pickers. EDIT THIS LIST to refine/extend the district names —
/// it's a representative starting set, not an exhaustive official list
/// (same convention as nineveh_neighborhoods.dart).
const List<String> ninevehDistricts = [
  'Mosul',
  'Tel Afar',
  'Sinjar',
  'Tel Kaif',
  'Al-Hamdaniya',
  'Al-Shikhan',
  'Al-Baaj',
  'Hatra',
  'Makhmour',
  'Al-Qayyarah',
];

/// Languages offered by the volunteer form's multi-select. Stored as a
/// comma-separated list of these keys; each key is translated in
/// app_translations.dart as `language_<key>`.
const List<String> volunteerLanguages = [
  'arabic',
  'english',
  'kurdish',
  'turkish',
  'german',
  'french',
  'chinese_japanese',
  'other',
];
