-- 077 — Three client specs:
--
-- 1. Eligible Recipient "Privacy": consent flags controlling what a grantor
--    may see about the recipient.
-- 2. "Third: Volunteer/Employee Registration — Join the Tawazon Team":
--    identification + contact information. Every column this section needs
--    (national_id, name_first/father/grandfather/family, tribe_clan,
--    title_surname, phone1, phone2, emergency_phone, email) already exists
--    from migrations 072/073 and is reused as-is — only the auto-generated
--    volunteer identification code is new here.
-- 3. "Future Development": the admin-controllable field rules already exist
--    (registration_field_rules + the admin endpoints). The rows below extend
--    that coverage to every field added by migrations 075-077, so the
--    administration can flip any of them Required <-> Optional with no code
--    change. The app's form now drives ALL of its required-field validation
--    from this table rather than a hardcoded list.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS consent_show_real_name TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS consent_share_info TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS volunteer_code TEXT NOT NULL DEFAULT '';

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  -- Eligible Recipient — "Privacy" consent section.
  ('recipient_consent_show_real_name', 'optional', 310),
  ('recipient_consent_share_info',     'optional', 311),
  -- Volunteer/Employee — "Identification Information".
  ('volunteer_national_id',      'required', 320),
  ('volunteer_name_parts',       'required', 321),
  ('volunteer_tribe_clan',       'optional', 322),
  ('volunteer_title_surname',    'required', 323),
  -- Volunteer/Employee — "Contact Information".
  ('volunteer_phone1',           'required', 324),
  ('volunteer_phone2',           'optional', 325),
  ('volunteer_emergency_phone',  'required', 326),
  ('volunteer_email',            'required', 327)
ON CONFLICT (field_key) DO NOTHING;
