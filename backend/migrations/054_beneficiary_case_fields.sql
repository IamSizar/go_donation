-- 054 — Note #32: the admin "Add Case" form was missing core beneficiary
-- fields the client's spec calls for (gender, date of birth, marital
-- status) that exist nowhere in the schema yet. Also seeds Field Rules
-- entries for every Add Case field so the admin can toggle each one
-- Required/Optional from Settings, same mechanism already used for the
-- mobile app's registration form (registration_field_rules, migration 045)
-- — reused here rather than inventing a second field-rules system, with a
-- "case_" key prefix so these never collide with the existing registration
-- field keys.

ALTER TABLE beneficiary_cases
  ADD COLUMN IF NOT EXISTS gender TEXT,
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS marital_status TEXT;

INSERT INTO registration_field_rules (field_key, required, display_order) VALUES
  ('case_public_title',          1, 101),
  ('case_full_name',             0, 102),
  ('case_national_id',           0, 103),
  ('case_gender',                0, 104),
  ('case_date_of_birth',         0, 105),
  ('case_marital_status',        0, 106),
  ('case_phone',                 0, 107),
  ('case_governorate',           0, 108),
  ('case_district',              0, 109),
  ('case_address',               0, 110),
  ('case_family_members_count',  0, 111),
  ('case_income_amount',         0, 112),
  ('case_housing_status',        0, 113),
  ('case_work_status',           0, 114),
  ('case_health_status',         0, 115),
  ('case_education_status',      0, 116),
  ('case_actual_needs',          0, 117)
ON CONFLICT (field_key) DO NOTHING;
