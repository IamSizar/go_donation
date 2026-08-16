// fieldRuleLabels — every label the Field Rules page (قواعد الحقول) prints for
// a `registration_field_rules` row, and the key prefixes that split those rows
// into one section per form.
//
// Why this file exists at all: a rule row carries only a raw column name
// (`recipient_tribe_clan`), and title-casing that name renders ENGLISH on an
// Arabic dashboard. So every seeded key is mapped to an i18n key instead —
// `field.*` / `dbfield.*`, the same namespaces the rest of the dashboard uses,
// so a label added here is translated once and reused everywhere.
//
// Two rules were followed when filling the maps below:
//
//   1. An existing key is REUSED wherever one already covers the concept
//      (`field.national_id`, `field.email`, `field.governorate`, …). Those are
//      already translated in all four locales, so reuse costs no translation.
//   2. A new label's English and Arabic are COPIED from the wording the
//      Flutter app already shows the applicant for that exact field
//      (`reg_*` in `humanitarian/lib/localization/app_translations.dart`),
//      not written here — so an admin toggling a field reads the same words
//      the applicant read. Kurdish (ckb/kmr) is deliberately NOT written: it
//      falls back to English and is listed in TRANSLATION_REQUEST.md for a
//      native speaker, per the project's standing rule that invented Kurdish
//      is worse than a visible English fallback.
//
// Keys are listed in `display_order`, i.e. the order the page shows them, so
// this file reads like the form it configures.

// humanize — last-resort label for a key no map covers: a rule row seeded by a
// future migration still renders something readable (in English) instead of a
// raw snake_case key. It is a fallback, not a feature — every English label
// left on this page is a key missing from one of the maps below, so a new
// migration that seeds a field key must add its entry here in the same change.
export const humanize = (k: string) =>
  k.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())

// ─── The app's own sign-up form (migration 045) ──────────────────────────────
// Fields every role fills in, seeded without a prefix. Role-specific fields
// live in the three prefixed maps below.
export const REGISTRATION_FIELD_LABEL_KEYS: Record<string, string> = {
  gender: 'field.gender',
  date_of_birth: 'field.date_of_birth',
  city: 'field.city',
  occupation: 'field.occupation',
  family_size: 'field.family_size',
  housing_status: 'field.housing_status',
  monthly_income: 'field.monthly_income',
  skills: 'field.skills',
  availability: 'field.availability',
  experience: 'field.experience',
}

// ─── Grantor registration (migration 072) ───────────────────────────────────
// "Grantor Registration" spec — the donor's own extra identification,
// contact and location fields.
export const GRANTOR_PREFIX = 'grantor_'
export const GRANTOR_FIELD_LABEL_KEYS: Record<string, string> = {
  national_id:     'field.national_id',
  name_parts:      'field.name_parts',
  title_surname:   'field.title_surname',
  phone1:          'field.phone1',
  phone2:          'field.phone2',
  email:           'field.email',
  gps_location:    'field.gps_location',
  governorate:     'field.governorate',
  education_level: 'field.education_level',
  personal_photo:  'field.profile_picture',
  id_photo:        'field.id_photo',
}

// ─── Eligible Recipient registration (migrations 073-077, 104) ──────────────
// The longest form in the app: identification, housing, education and
// employment, household composition, health, attachments, assets, needs,
// social accounts, and the two privacy consents.
export const RECIPIENT_PREFIX = 'recipient_'
export const RECIPIENT_FIELD_LABEL_KEYS: Record<string, string> = {
  national_id:               'field.national_id',
  name_parts:                'field.name_parts',
  tribe_clan:                'field.tribe_clan',
  title_surname:             'field.title_surname',
  email:                     'field.email',
  phone1:                    'field.phone1',
  phone2:                    'field.phone2',
  emergency_phone:           'field.emergency_phone',
  nationality:               'field.nationality',
  marital_status:            'field.marital_status',
  residency_status:          'field.residency_status',
  governorate:               'field.governorate',
  housing_side:              'field.housing_side',
  neighborhood:              'field.neighborhood',
  nearest_landmark:          'field.nearest_landmark',
  gps_location:              'field.gps_location',
  housing_type:              'field.housing_type',
  rental_amount:             'field.rental_amount',
  housing_area:              'field.housing_area',
  floors_count:              'field.floors_count',
  rooms_count:               'field.rooms_count',
  families_count:            'field.families_count',
  education_level:           'field.education_level',
  other_certificate:         'field.other_certificate',
  certificates_count:        'field.certificates_count',
  previous_occupation:       'field.previous_occupation',
  job_description:           'field.job_description',
  working_hours:             'field.working_hours',
  is_employed:               'field.is_employed',
  workplace:                 'field.workplace',
  wage_amount:               'field.wage_amount',
  registered_social_welfare: 'field.registered_social_welfare',
  registered_unemployed:     'field.registered_unemployed',
  household_employees:       'field.household_employees',
  working_members:           'field.working_members',
  men_count:                 'field.men_count',
  women_count:               'field.women_count',
  male_children_count:       'field.male_children_count',
  female_children_count:     'field.female_children_count',
  age_0_5_count:             'field.age_0_5_count',
  age_5_10_count:            'field.age_5_10_count',
  age_10_15_count:           'field.age_10_15_count',
  age_15_25_count:           'field.age_15_25_count',
  age_25_40_count:           'field.age_25_40_count',
  age_40_plus_count:         'field.age_40_plus_count',
  students_count:            'field.students_count',
  orphans_count:             'field.orphans_count',
  widows_count:              'field.widows_count',
  divorced_count:            'field.divorced_count',
  height:                    'field.height',
  weight:                    'field.weight',
  smoking_status:            'field.smoking_status',
  eyesight_condition:        'field.eyesight_condition',
  has_disability:            'field.has_disability',
  disability_type:           'field.disability_type',
  household_disabled:        'field.household_disabled',
  chronic_illnesses:         'field.chronic_illnesses',
  medical_conditions_count:  'field.medical_conditions_count',
  medical_conditions_desc:   'field.medical_conditions_desc',
  personal_photo:            'field.profile_picture',
  id_photo:                  'field.id_photo',
  ration_card_photo:         'field.ration_card_photo',
  property_proof_photo:      'field.property_proof_photo',
  medical_report_photo:      'field.medical_report_photo',
  house_facade_photo:        'field.house_facade_photo',
  house_inside_photo:        'field.house_inside_photo',
  house_outside_photo:       'field.house_outside_photo',
  available_furniture:       'field.available_furniture',
  owns_car:                  'field.owns_car',
  needs_description:         'field.needs_description',
  social_facebook:           'field.social_facebook',
  social_instagram:          'field.social_instagram',
  social_telegram:           'field.social_telegram',
  consent_show_real_name:    'field.consent_show_real_name',
  consent_share_info:        'field.consent_share_info',
}

// ─── Volunteer / employee registration (migrations 077-078) ─────────────────
// "Join the Tawazon Team" — identification and contact, then personal,
// housing, social, educational/professional, attachments and social accounts.
export const VOLUNTEER_PREFIX = 'volunteer_'
export const VOLUNTEER_FIELD_LABEL_KEYS: Record<string, string> = {
  national_id:           'field.national_id',
  name_parts:            'field.name_parts',
  tribe_clan:            'field.tribe_clan',
  title_surname:         'field.title_surname',
  phone1:                'field.phone1',
  phone2:                'field.phone2',
  emergency_phone:       'field.emergency_phone',
  email:                 'field.email',
  date_of_birth:         'field.date_of_birth',
  gender:                'field.gender',
  nationality:           'field.nationality',
  languages:             'field.languages',
  governorate:           'field.governorate',
  district:              'field.district',
  housing_side:          'field.housing_side',
  neighborhood:          'field.neighborhood',
  nearest_landmark:      'field.nearest_landmark',
  housing_type:          'field.housing_type',
  housing_area:          'field.housing_area',
  family_size:           'field.family_size',
  gps_location:          'field.gps_location',
  marital_status:        'field.marital_status',
  education_level:       'field.education_level',
  other_certificate:     'field.other_certificate',
  occupation:            'field.occupation',
  previous_occupation:   'field.previous_occupation',
  skills:                'field.skills',
  experience:            'field.experience',
  golden_square_photo:   'field.golden_square_photo',
  id_photo:              'field.id_photo',
  ration_card_photo:     'field.ration_card_photo',
  residence_card_photo:  'field.residence_card_photo',
  passport_photo:        'field.passport_photo',
  personal_photo:        'field.profile_picture',
  graduation_cert_photo: 'field.graduation_cert_photo',
  cv_photo:              'field.cv_photo',
  social_facebook:       'field.social_facebook',
  social_instagram:      'field.social_instagram',
  social_telegram:       'field.social_telegram',
  social_other:          'field.social_other',
}

// ─── Add Case form (Note #32, migration 054) ────────────────────────────────
// The dashboard's own Add Case (Recipient) window. Reuses the exact field.*
// labels that form itself shows, so an admin recognizes them as the same
// fields.
export const CASE_PREFIX = 'case_'
export const CASE_FIELD_LABEL_KEYS: Record<string, string> = {
  public_title: 'field.public_title_en',
  full_name: 'field.full_name',
  national_id: 'field.national_id',
  gender: 'field.gender',
  date_of_birth: 'field.date_of_birth',
  marital_status: 'field.marital_status',
  phone: 'field.phone',
  governorate: 'field.governorate',
  district: 'field.district',
  address: 'field.address',
  family_members_count: 'field.family_members',
  income_amount: 'field.income_amount',
  housing_status: 'field.housing_status',
  work_status: 'field.work_status',
  health_status: 'field.health_status',
  education_status: 'field.education_status',
  actual_needs: 'field.actual_needs',
}

// ─── Marriage / Engagement form (Note #33, migrations 056, 067, 079-082) ────
// Same label-reuse pattern as the case fields above.
export const MARRIAGE_PREFIX = 'marriage_'
export const MARRIAGE_FIELD_LABEL_KEYS: Record<string, string> = {
  gender: 'field.gender',
  age: 'dbfield.age',
  city: 'field.city',
  governorate: 'field.governorate',
  social_summary: 'field.social_summary',
  private_notes: 'field.private_notes',
  marital_status: 'field.marital_status',
  religion: 'field.religion',
  employment_status: 'field.employment_status',
  weight: 'field.weight',
  height: 'field.height',
}

// ─── Add New User window (Note #34, migration 057) ──────────────────────────
// The dashboard's own admin-only user form, kept independent from the app's
// sign-up rules above since it is a separate screen.
export const NEW_USER_PREFIX = 'user_'
export const NEW_USER_FIELD_LABEL_KEYS: Record<string, string> = {
  full_name: 'field.full_name',
  gender: 'field.gender',
  date_of_birth: 'field.date_of_birth',
  address: 'field.address',
  city: 'field.city',
  occupation: 'field.occupation',
  housing_status: 'field.housing_status',
  family_size: 'field.family_size',
  monthly_income: 'field.monthly_income',
  availability: 'field.availability',
  experience: 'field.experience',
  skills: 'field.skills',
  profile_picture: 'field.profile_picture',
}

// ALL_PREFIXES — every prefix that has its own section. The sign-up section
// is the leftover: it renders the rows that match NONE of these, so adding a
// prefix here is all it takes to stop new rows piling up under "Registration".
export const ALL_PREFIXES = [
  GRANTOR_PREFIX,
  RECIPIENT_PREFIX,
  VOLUNTEER_PREFIX,
  CASE_PREFIX,
  MARRIAGE_PREFIX,
  NEW_USER_PREFIX,
]
