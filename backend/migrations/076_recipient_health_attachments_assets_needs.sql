-- 076 — Eligible Recipient Registration spec: "Health Information",
-- "Attachments", "Assets", "Needs", and "Social Media Accounts" sections.
--
-- Reused as-is, NOT duplicated here:
--   * profile_picture / id_photo_path (migration 072) — the spec's "Personal
--     photo" and "National Card photo" attachments. Previously captured for
--     the grantor role only; the recipient form now uses the same columns.
--   * social_facebook / social_instagram / social_telegram (migration 073) —
--     the spec's "Social Media Accounts" section, until now only writable
--     from the Privacy Settings screen.
ALTER TABLE user_profiles
  -- Health Information.
  ADD COLUMN IF NOT EXISTS height TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS weight TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS smoking_status TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS eyesight_condition TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS has_disability TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS disability_type TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS household_disabled_count TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS chronic_illnesses TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS medical_conditions_count TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS medical_conditions_desc TEXT NOT NULL DEFAULT '',
  -- Attachments (relative paths, served at /images/*).
  ADD COLUMN IF NOT EXISTS ration_card_photo_path TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS property_proof_photo_path TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS medical_report_photo_path TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS house_facade_photo_path TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS house_inside_photo_path TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS house_outside_photo_path TEXT NOT NULL DEFAULT '',
  -- Assets.
  ADD COLUMN IF NOT EXISTS available_furniture TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS owns_car TEXT NOT NULL DEFAULT '',
  -- Needs.
  ADD COLUMN IF NOT EXISTS needs_description TEXT NOT NULL DEFAULT '';

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  ('recipient_height',                 'optional', 280),
  ('recipient_weight',                 'optional', 281),
  ('recipient_smoking_status',         'optional', 282),
  ('recipient_eyesight_condition',     'optional', 283),
  ('recipient_has_disability',         'optional', 284),
  ('recipient_disability_type',        'optional', 285),
  ('recipient_household_disabled',     'optional', 286),
  ('recipient_chronic_illnesses',      'optional', 287),
  ('recipient_medical_conditions_count','optional', 288),
  ('recipient_medical_conditions_desc','optional', 289),
  ('recipient_personal_photo',         'optional', 290),
  ('recipient_id_photo',               'optional', 291),
  ('recipient_ration_card_photo',      'optional', 292),
  ('recipient_property_proof_photo',   'optional', 293),
  ('recipient_medical_report_photo',   'optional', 294),
  ('recipient_house_facade_photo',     'optional', 295),
  ('recipient_house_inside_photo',     'optional', 296),
  ('recipient_house_outside_photo',    'optional', 297),
  ('recipient_available_furniture',    'optional', 298),
  ('recipient_owns_car',               'optional', 299),
  ('recipient_needs_description',      'optional', 300),
  ('recipient_social_facebook',        'optional', 301),
  ('recipient_social_instagram',       'optional', 302),
  ('recipient_social_telegram',        'optional', 303)
ON CONFLICT (field_key) DO NOTHING;
