-- 080 — "Fourth: My Engagement / Marriage Section" spec:
-- "Personal Information".
--
-- Reused as-is, NOT duplicated: gender and marital_status already exist on
-- marriage_profiles (migrations 001 / 067). The spec widens marital status
-- from 4 options to 8 — that's a form/translation change, not a schema one,
-- since the column is a free VARCHAR(32).
ALTER TABLE marriage_profiles
  ADD COLUMN IF NOT EXISTS nationality TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS residency_status TEXT NOT NULL DEFAULT '';

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  ('marriage_nationality',      'required', 380),
  ('marriage_residency_status', 'optional', 381)
ON CONFLICT (field_key) DO NOTHING;
