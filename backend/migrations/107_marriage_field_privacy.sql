-- 107 — L19: per-field privacy on the engagement ("خطوبتي") profile.
--
-- THE GAP THIS CLOSES
-- The engagement form offers ONE whole-profile audience dropdown
-- (visibility_level, three values), which cannot express "show my age, hide my
-- photo". The app deliberately did NOT ship a per-field picker, and it was
-- right not to: there was nowhere to store the answer, and nothing that would
-- have honoured it. marriage.Store.List SELECTs every field — gender, age,
-- city, religion, weight, height, photo — and masks none of them. A picker on
-- its own would have been a row of controls that changed nothing, which on a
-- matchmaking profile is a privacy incident rather than a cosmetic gap.
--
-- This migration adds the storage. The masking itself lives in
-- internal/marriage (Store.List) and is what actually makes the picker honest.
--
-- ADDITIVE
-- One new column with a safe empty default, and one new table. No column is
-- dropped, no type changed, no existing value rewritten, and no backfill is
-- needed — an empty list means "hide nothing", which is exactly the behaviour
-- every existing profile has today.

-- The per-profile answer. Same shape and same semantics as
-- user_profiles.field_privacy (migration 040): the list of field keys the
-- OWNER hides from other users. Kept on marriage_profiles rather than reusing
-- the user-profile column because the two profiles are separate objects — one
-- person may show their photo on their user profile and hide it here.
ALTER TABLE marriage_profiles
  ADD COLUMN IF NOT EXISTS field_privacy TEXT[] NOT NULL DEFAULT '{}';

-- The catalogue the picker renders, following the same data-driven pattern
-- privacy_field_options established in migration 083: insert a row here and a
-- new switch appears in the app, with no code change and no app release.
--
--   field_key      — MATCHES THE marriage_profiles COLUMN NAME, and matches
--                    what gets stored in marriage_profiles.field_privacy.
--   label_key      — app translation key; the app falls back to the field key
--                    when the key has no translation, so a brand-new row is
--                    usable immediately.
--   default_hidden — whether the field starts hidden. Note that, as with the
--                    user catalogue, the server enforces only choices a user
--                    actually SAVED; this column tells the app how to
--                    pre-tick a picker the user has never opened.
--   enabled        — lets staff retire an option without deleting history.
--
-- WHY A SEPARATE TABLE INSTEAD OF ROWS IN privacy_field_options
-- That table's PRIMARY KEY is field_key alone, and the engagement profile
-- shares several column names with the user profile (gender, age, city). The
-- rows could not coexist without prefixing every marriage key, which would
-- mean marriage_profiles.field_privacy stored 'marriage_gender' for a column
-- literally called gender — a translation table to maintain forever. Keys here
-- are the real column names, so the masking code maps key -> column directly.
-- Adding a scope column to the shared table was the other option and was
-- rejected: it would have needed the existing primary key replaced, which is
-- a destructive change.
CREATE TABLE IF NOT EXISTS marriage_privacy_field_options (
  field_key      VARCHAR(64) PRIMARY KEY,
  label_key      VARCHAR(96) NOT NULL DEFAULT '',
  default_hidden BOOLEAN     NOT NULL DEFAULT FALSE,
  enabled        BOOLEAN     NOT NULL DEFAULT TRUE,
  display_order  INTEGER     NOT NULL DEFAULT 0,
  updated_at     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- The ten fields the browse feed actually shows about a person. Deliberately
-- NOT offered: profile_code (the handle that replaces a name — hiding it would
-- leave nothing to refer to the profile by), and status / subscription_status /
-- visibility_level, which are not personal details.
--
-- EVERY label_key BELOW ALREADY EXISTS IN ALL FOUR LOCALES (en/ar/ckb/kmr) in
-- humanitarian/lib/localization/app_translations.dart — they are the labels
-- the engagement FORM already prints above these same fields, so the picker
-- reads in the user's language on day one and this migration adds NO new
-- translation work. Checked key by key against the four maps before choosing
-- them; marriage_summary in particular is the key the form itself already maps
-- social_summary to (marriage_form_screen.dart). A new switch added later
-- should reuse an existing key the same way, or go through
-- TRANSLATION_REQUEST.md — never ship invented Kurdish.
INSERT INTO marriage_privacy_field_options (field_key, label_key, default_hidden, display_order) VALUES
  ('photo_url',         'marriage_photo',             false,  10),
  ('age',               'marriage_age',               false,  20),
  ('gender',            'marriage_gender',            false,  30),
  ('city',              'marriage_city',              false,  40),
  ('marital_status',    'marriage_marital_status',    false,  50),
  ('religion',          'marriage_religion',          false,  60),
  ('employment_status', 'marriage_employment_status', false,  70),
  ('weight_kg',         'marriage_weight',            false,  80),
  ('height_cm',         'marriage_height',            false,  90),
  ('social_summary',    'marriage_summary',           false, 100)
ON CONFLICT (field_key) DO NOTHING;

-- NO INDEX IS ADDED HERE, DELIBERATELY.
-- field_privacy is never a WHERE condition: it is read as part of the row that
-- is already being selected, and applied in Go. An index on it would be paid
-- for on every profile write and never used. The catalogue table is a
-- ten-row lookup read once per screen and needs nothing beyond its primary
-- key.
--
-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- This repo's runner (internal/db/migrate.go) is forward-only and records each
-- file in schema_migrations; there is no .down.sql convention, so the reversal
-- is recorded here and was EXECUTED against a local database before this
-- migration was committed:
--
--   ALTER TABLE marriage_profiles DROP COLUMN IF EXISTS field_privacy;
--   DROP TABLE IF EXISTS marriage_privacy_field_options;
--   DELETE FROM schema_migrations WHERE version = '107_marriage_field_privacy.sql';
--
-- Reversing discards the per-field choices users had saved and returns every
-- engagement profile to "show everything", which is the pre-migration
-- behaviour. Nothing else is affected: no existing column is touched, so
-- profiles, photos and visibility_level survive a down-and-up cycle unchanged.
