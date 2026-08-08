-- 073 — Two client specs in one migration (both touch user_profiles):
--
-- 1. "Privacy Settings" (grantor): choose real name vs. an alias/nickname
--    for display, plus optional social media links.
-- 2. "Eligible Recipient Registration": the beneficiary registration form
--    was missing fields (national ID, four-part name, title/surname, phone1/
--    phone2, and email are already covered by migration 072's grantor
--    columns — reused here, not duplicated). New columns: tribe/clan,
--    emergency contact phone, nationality, marital status, residency
--    status, and an auto-generated recipient identification code.

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS display_name_mode TEXT NOT NULL DEFAULT 'real',
  ADD COLUMN IF NOT EXISTS alias_name TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS social_facebook TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS social_instagram TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS social_telegram TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS tribe_clan TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS emergency_phone TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS nationality TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS marital_status TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS residency_status TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS recipient_code TEXT NOT NULL DEFAULT '';

ALTER TABLE user_profiles
  ADD CONSTRAINT user_profiles_display_name_mode_check
  CHECK (display_name_mode IN ('real', 'alias'));

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  ('recipient_national_id',    'required', 220),
  ('recipient_name_parts',     'required', 221),
  ('recipient_tribe_clan',     'optional', 222),
  ('recipient_title_surname',  'required', 223),
  ('recipient_email',          'required', 224),
  ('recipient_phone1',         'required', 225),
  ('recipient_phone2',         'optional', 226),
  ('recipient_emergency_phone','required', 227),
  ('recipient_nationality',    'required', 228),
  ('recipient_marital_status', 'required', 229),
  ('recipient_residency_status','required', 230)
ON CONFLICT (field_key) DO NOTHING;
