-- 082 — "Fourth: My Engagement / Marriage Section" spec, final sections:
-- "Educational and Employment Information", "Personal and Health
-- Information", "Assets", "Needs and Requirements", "Attachments", and
-- "Social Media Accounts".
--
-- Reused as-is, NOT duplicated (already on marriage_profiles):
--   date_of_birth (migration 079), height_cm / weight_kg / religion /
--   employment_status (067), photo_url — the spec's "Personal photo" (011).
ALTER TABLE marriage_profiles
  -- Educational and Employment Information.
  ADD COLUMN IF NOT EXISTS education_level TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS other_certificate TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS certificates_count TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS occupation TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS previous_occupation TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS job_description TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS working_hours TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS monthly_income TEXT NOT NULL DEFAULT '',
  -- Personal and Health Information.
  ADD COLUMN IF NOT EXISTS skin_tone TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS family_members_count TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS children_count TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS smoking_status TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS eyesight_condition TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS has_disability TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS disability_type TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS chronic_illnesses TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS ethnicity TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS skills TEXT NOT NULL DEFAULT '',
  -- Assets.
  ADD COLUMN IF NOT EXISTS owns_car TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS owns_house TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS owns_shop TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS owns_company TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS owns_land TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS other_assets TEXT NOT NULL DEFAULT '',
  -- Needs and Requirements.
  ADD COLUMN IF NOT EXISTS partner_requirements TEXT NOT NULL DEFAULT '',
  -- Attachments (uploaded via POST /api/uploads, stored as returned paths).
  ADD COLUMN IF NOT EXISTS golden_square_url TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS graduation_cert_url TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS cv_url TEXT NOT NULL DEFAULT '',
  -- Social Media Accounts.
  ADD COLUMN IF NOT EXISTS social_facebook TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS social_instagram TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS social_telegram TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS social_other TEXT NOT NULL DEFAULT '';

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  -- Educational and Employment Information.
  ('marriage_education_level',     'optional', 410),
  ('marriage_other_certificate',   'optional', 411),
  ('marriage_certificates_count',  'optional', 412),
  ('marriage_occupation',          'optional', 413),
  ('marriage_previous_occupation', 'optional', 414),
  ('marriage_job_description',     'optional', 415),
  ('marriage_working_hours',       'optional', 416),
  ('marriage_monthly_income',      'optional', 417),
  -- Personal and Health Information.
  ('marriage_skin_tone',           'optional', 418),
  ('marriage_family_members',      'optional', 419),
  ('marriage_children_count',      'optional', 420),
  ('marriage_smoking_status',      'optional', 421),
  ('marriage_eyesight_condition',  'optional', 422),
  ('marriage_has_disability',      'optional', 423),
  ('marriage_disability_type',     'optional', 424),
  ('marriage_chronic_illnesses',   'optional', 425),
  ('marriage_ethnicity',           'optional', 426),
  ('marriage_skills',              'optional', 427),
  -- Assets.
  ('marriage_owns_car',            'optional', 428),
  ('marriage_owns_house',          'optional', 429),
  ('marriage_owns_shop',           'optional', 430),
  ('marriage_owns_company',        'optional', 431),
  ('marriage_owns_land',           'optional', 432),
  ('marriage_other_assets',        'optional', 433),
  -- Needs and Requirements.
  ('marriage_partner_requirements','optional', 434),
  -- Attachments.
  ('marriage_personal_photo',      'optional', 435),
  ('marriage_golden_square',       'optional', 436),
  ('marriage_graduation_cert',     'optional', 437),
  ('marriage_cv',                  'optional', 438),
  -- Social Media Accounts.
  ('marriage_social_facebook',     'optional', 439),
  ('marriage_social_instagram',    'optional', 440),
  ('marriage_social_telegram',     'optional', 441),
  ('marriage_social_other',        'optional', 442)
ON CONFLICT (field_key) DO NOTHING;
