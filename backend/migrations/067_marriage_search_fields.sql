-- Client note — Marriage "Search" should filter on marital status, religion,
-- employment status, weight, and height too, and every marriage filter
-- (including the existing gender/age ones) should be staff-configurable —
-- an employee decides which filters are actually usable.
ALTER TABLE marriage_profiles
  ADD COLUMN IF NOT EXISTS marital_status VARCHAR(32),
  ADD COLUMN IF NOT EXISTS religion VARCHAR(64),
  ADD COLUMN IF NOT EXISTS employment_status VARCHAR(32),
  ADD COLUMN IF NOT EXISTS weight_kg INTEGER,
  ADD COLUMN IF NOT EXISTS height_cm INTEGER;

-- Reuses the existing registration_field_rules table (already the
-- staff-configurable mechanism for the marriage registration form) instead
-- of a parallel config table — a field is now independently: required on
-- the form, hidden from the form, AND/OR usable as a search filter.
ALTER TABLE registration_field_rules
  ADD COLUMN IF NOT EXISTS searchable BOOLEAN NOT NULL DEFAULT false;

-- The existing gender/age filters are already functionally "on" today —
-- mark them searchable so staff manage ALL marriage filters in one place,
-- not just the new ones.
UPDATE registration_field_rules SET searchable = true
  WHERE field_key IN ('marriage_gender', 'marriage_age');

INSERT INTO registration_field_rules (field_key, state, display_order, searchable) VALUES
  ('marriage_marital_status',    'optional', 206, false),
  ('marriage_religion',          'optional', 207, false),
  ('marriage_employment_status', 'optional', 208, false),
  ('marriage_weight',            'optional', 209, false),
  ('marriage_height',            'optional', 210, false)
ON CONFLICT (field_key) DO NOTHING;
