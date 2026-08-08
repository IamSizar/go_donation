-- 079 — "Fourth: My Engagement / Marriage Section" spec:
-- "Identification Information" on the marriage registration form.
--
-- Reused as-is, NOT duplicated: marriage_profiles.profile_code already is the
-- spec's "automatically generated identification code" (assigned in
-- marriage.Store.Insert as M-YYYYMMDD-XXXXXX).
--
-- These live on marriage_profiles rather than reusing user_profiles' columns:
-- a marriage profile is a separate entity with its own visibility_level and
-- review status, and the applicant may present different contact details here
-- than on their main account.
ALTER TABLE marriage_profiles
  ADD COLUMN IF NOT EXISTS national_id TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS name_first TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS name_father TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS name_grandfather TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS name_family TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS tribe_clan TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS title_surname TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS email TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS phone1 TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS phone2 TEXT NOT NULL DEFAULT '';

-- The marriage form reads these with the 'marriage_' prefix stripped, so the
-- keys here stay consistent with the existing marriage_* rules.
INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  ('marriage_national_id',      'required', 370),
  ('marriage_name_parts',       'required', 371),
  ('marriage_tribe_clan',       'optional', 372),
  ('marriage_title_surname',    'optional', 373),
  ('marriage_date_of_birth',    'required', 374),
  ('marriage_email',            'required', 375),
  ('marriage_phone1',           'required', 376),
  ('marriage_phone2',           'optional', 377)
ON CONFLICT (field_key) DO NOTHING;
