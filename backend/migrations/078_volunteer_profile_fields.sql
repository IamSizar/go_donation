-- 078 — "Third: Volunteer/Employee Registration" spec, remaining sections:
-- Personal Information, Housing Information, Social Information, Educational
-- and Professional Information, Attachments, and Social Media Accounts.
--
-- Reused as-is, NOT duplicated (all already exist from migrations 072-077):
--   date_of_birth, gender, nationality, governorate, housing_side,
--   neighborhood, nearest_landmark, housing_type, housing_area, family_size,
--   gps_lat/gps_lng, marital_status, education_level, other_certificate,
--   occupation, previous_occupation, skills, experience, profile_picture
--   (formal personal photo), id_photo_path (unified National Card / ID),
--   ration_card_photo_path, social_facebook/instagram/telegram.
ALTER TABLE user_profiles
  -- Personal Information.
  ADD COLUMN IF NOT EXISTS languages TEXT NOT NULL DEFAULT '',
  -- Housing Information — the Nineveh district level, between governorate
  -- and the side/neighborhood pickers.
  ADD COLUMN IF NOT EXISTS district TEXT NOT NULL DEFAULT '',
  -- Attachments.
  ADD COLUMN IF NOT EXISTS golden_square_photo_path TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS residence_card_photo_path TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS passport_photo_path TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS graduation_cert_photo_path TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS cv_photo_path TEXT NOT NULL DEFAULT '',
  -- Social Media Accounts.
  ADD COLUMN IF NOT EXISTS social_other TEXT NOT NULL DEFAULT '';

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  -- Personal Information.
  ('volunteer_date_of_birth',      'required', 330),
  ('volunteer_gender',             'required', 331),
  ('volunteer_nationality',        'required', 332),
  ('volunteer_languages',          'optional', 333),
  -- Housing Information.
  ('volunteer_governorate',        'required', 334),
  ('volunteer_district',           'optional', 335),
  ('volunteer_housing_side',       'optional', 336),
  ('volunteer_neighborhood',       'optional', 337),
  ('volunteer_nearest_landmark',   'optional', 338),
  ('volunteer_housing_type',       'optional', 339),
  ('volunteer_housing_area',       'optional', 340),
  ('volunteer_family_size',        'optional', 341),
  ('volunteer_gps_location',       'optional', 342),
  -- Social Information.
  ('volunteer_marital_status',     'optional', 343),
  -- Educational and Professional Information.
  ('volunteer_education_level',    'optional', 344),
  ('volunteer_other_certificate',  'optional', 345),
  ('volunteer_occupation',         'optional', 346),
  ('volunteer_previous_occupation','optional', 347),
  ('volunteer_skills',             'optional', 348),
  ('volunteer_experience',         'optional', 349),
  -- Attachments.
  ('volunteer_golden_square_photo','optional', 350),
  ('volunteer_id_photo',           'optional', 351),
  ('volunteer_ration_card_photo',  'optional', 352),
  ('volunteer_residence_card_photo','optional', 353),
  ('volunteer_passport_photo',     'optional', 354),
  ('volunteer_personal_photo',     'optional', 355),
  ('volunteer_graduation_cert_photo','optional', 356),
  ('volunteer_cv_photo',           'optional', 357),
  -- Social Media Accounts.
  ('volunteer_social_facebook',    'optional', 358),
  ('volunteer_social_instagram',   'optional', 359),
  ('volunteer_social_telegram',    'optional', 360),
  ('volunteer_social_other',       'optional', 361)
ON CONFLICT (field_key) DO NOTHING;
