-- 083 — Two client specs:
--
-- 1. "Privacy Settings" + its "Future Development" note: the user picks which
--    of their details other users may see. The per-user choice already exists
--    (user_profiles.field_privacy TEXT[], migration 040) and is free-form, but
--    the *catalogue* of toggleable fields was hardcoded in the mobile app —
--    so adding one meant a code change and an app release. This table makes
--    the catalogue data-driven: insert a row here and the option appears in
--    the app, no reprogramming or redeploy.
--
--      field_key     — matches the key stored in user_profiles.field_privacy.
--      label_key     — app translation key; the app falls back to field_key
--                      when the key has no translation, so a brand-new row
--                      is still usable immediately.
--      default_hidden— whether the field starts hidden for new users.
--      enabled       — lets staff retire an option without deleting history.
CREATE TABLE IF NOT EXISTS privacy_field_options (
  field_key      VARCHAR(64) PRIMARY KEY,
  label_key      VARCHAR(96) NOT NULL DEFAULT '',
  default_hidden BOOLEAN     NOT NULL DEFAULT FALSE,
  enabled        BOOLEAN     NOT NULL DEFAULT TRUE,
  display_order  INTEGER     NOT NULL DEFAULT 0,
  updated_at     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- The six the app shipped with, plus the spec's additions (educational
-- qualification, occupation, governorate). "Any other information selected by
-- the user" / "Additional fields as needed" are served by inserting more rows.
INSERT INTO privacy_field_options (field_key, label_key, default_hidden, display_order) VALUES
  ('full_name',       'pf_full_name',       false, 10),
  ('phone',           'pf_phone',           true,  20),
  ('gender',          'pf_gender',          false, 30),
  ('address',         'pf_address',         true,  40),
  ('date_of_birth',   'pf_dob',             false, 50),
  ('profile_picture', 'pf_picture',         false, 60),
  ('age',             'pf_age',             false, 70),
  ('education_level', 'pf_education_level', false, 80),
  ('occupation',      'pf_occupation',      false, 90),
  ('governorate',     'pf_governorate',     false, 100)
ON CONFLICT (field_key) DO NOTHING;

-- 2. "Fifth: Continue as Guest" — the guest browsing scope is already
--    admin-configurable per screen (guest_settings, migration 021). The spec
--    names three areas the canonical screen list didn't cover yet, so they
--    could not be toggled from the Admin Dashboard. Rows here are only
--    overrides; the canonical list + defaults live in internal/guest.
INSERT INTO guest_settings (screen, enabled) VALUES
  ('statistics', true),
  ('services',   true),
  ('support',    true)
ON CONFLICT (screen) DO NOTHING;
