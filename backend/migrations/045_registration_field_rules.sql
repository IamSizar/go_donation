-- 045 — Admin-configurable registration field rules (#43). One row per
-- optional sign-up field; `required=1` makes the app enforce it. Core fields
-- (full_name, address) stay required in code and are not listed here.
-- Idempotent.
CREATE TABLE IF NOT EXISTS registration_field_rules (
  field_key     VARCHAR(48) PRIMARY KEY,
  required      SMALLINT NOT NULL DEFAULT 0,
  display_order INTEGER  NOT NULL DEFAULT 0
);

INSERT INTO registration_field_rules (field_key, display_order) VALUES
  ('gender', 1),
  ('date_of_birth', 2),
  ('city', 3),
  ('occupation', 4),
  ('family_size', 5),
  ('housing_status', 6),
  ('monthly_income', 7),
  ('skills', 8),
  ('availability', 9),
  ('experience', 10)
ON CONFLICT (field_key) DO NOTHING;
