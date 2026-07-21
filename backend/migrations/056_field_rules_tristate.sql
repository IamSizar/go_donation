-- 056 — Note 33: Field Rules gains a third state. Until now a field was only
-- required (1) or optional (0); the client also wants "hidden" — a field the
-- admin can switch off entirely, not just make optional. Replaces the
-- `required SMALLINT` column with a `state` enum (required|optional|hidden);
-- nothing else in the schema reads `required` directly (confirmed — only
-- field_rules.go, which is updated in the same change), so this is a clean
-- cutover, not an additive column.
--
-- Also seeds field-rule keys for the Marriage/Engagement form (gender, age,
-- city, social_summary, private_notes) — the one registration-style form
-- that had no Field Rules coverage at all (unlike the general sign-up form,
-- migration 045, and the Beneficiary case form, migration 054).

ALTER TABLE registration_field_rules ADD COLUMN IF NOT EXISTS state VARCHAR(10);

UPDATE registration_field_rules
   SET state = CASE WHEN required = 1 THEN 'required' ELSE 'optional' END
 WHERE state IS NULL;

ALTER TABLE registration_field_rules ALTER COLUMN state SET NOT NULL;
ALTER TABLE registration_field_rules ALTER COLUMN state SET DEFAULT 'optional';
ALTER TABLE registration_field_rules
  ADD CONSTRAINT registration_field_rules_state_check
  CHECK (state IN ('required', 'optional', 'hidden'));

ALTER TABLE registration_field_rules DROP COLUMN IF EXISTS required;

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  ('marriage_gender',         'optional', 201),
  ('marriage_age',            'optional', 202),
  ('marriage_city',           'optional', 203),
  ('marriage_social_summary', 'optional', 204),
  ('marriage_private_notes',  'optional', 205)
ON CONFLICT (field_key) DO NOTHING;
