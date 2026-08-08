-- 072 — Grantor Registration spec: the grantor (donor) registration form was
-- missing a set of fields the client's spec requires (national ID, the
-- four-part legal name, title/surname, a second contact phone, email, GPS
-- location, governorate, educational attainment, and an ID card photo —
-- profile_picture already covers the personal photo). All nullable/optional
-- at the DB layer; the app enforces which ones are required for the grantor
-- role client-side, same pattern as the existing role-specific extras
-- (family_size/housing_status for beneficiaries, skills/availability for
-- volunteers).
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS national_id TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS name_first TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS name_father TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS name_grandfather TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS name_family TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS title_surname TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS phone1 TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS phone2 TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS email TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS gps_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS gps_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS governorate TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS education_level TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS id_photo_path TEXT NOT NULL DEFAULT '';

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  ('grantor_national_id',       'optional', 200),
  ('grantor_name_parts',        'required', 201),
  ('grantor_title_surname',     'required', 202),
  ('grantor_phone1',            'optional', 203),
  ('grantor_phone2',            'optional', 204),
  ('grantor_email',             'optional', 205),
  ('grantor_gps_location',      'optional', 206),
  ('grantor_governorate',       'required', 207),
  ('grantor_education_level',   'required', 208),
  ('grantor_personal_photo',    'optional', 209),
  ('grantor_id_photo',          'optional', 210)
ON CONFLICT (field_key) DO NOTHING;
