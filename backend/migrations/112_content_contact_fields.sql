-- 112 — K13: تواصل معنا had no contact details, only a sentence.
--
-- THE GAP THIS CLOSES
-- The client asked the Contact page to carry a logo, a phone number, WhatsApp,
-- an email address, social media links and an address. NONE of them existed as
-- fields. `app_content` (migration 025) holds one title and one body per locale
-- and nothing else, so the shipped Contact page is a single sentence — verified
-- on a freshly-migrated database: 11 columns, and `contact`'s body_en is 53
-- characters of prose with no number and no address in it. Nothing on that
-- screen is tappable because there is nothing structured to tap.
--
-- This migration builds the FIELDS. It seeds no values: the owner supplies the
-- real number, address and links later, from the dashboard.
--
-- WHY ON app_content AND NOT A NEW TABLE
-- These are one-per-page attributes, and migration 099 already established that
-- each section carries its OWN contact details ("the marriage service and the
-- city guide must contain details, phone numbers and social media links
-- DIFFERENT from those used for humanitarian assistance") by giving each its
-- own app_content row. Columns on that row inherit that split for free; a side
-- table would re-implement the same one-to-one relationship with a join.
--
-- social_links REUSES THE EXISTING SHAPE — one link per line, commas also
-- tolerated — that `partners.social_links` (035) and
-- `city_directory_entries.social_links` (100) already store and that the app
-- already parses (shared/utils/social_links.dart). A third format would need a
-- third parser.
--
-- ADDITIVE ONLY
-- Nine new columns, nothing dropped, no type changed, and NO BACKFILL: there is
-- no existing value anywhere to derive a phone number or an address from, and
-- inventing one is exactly what must not happen here. Every page starts with
-- these fields empty, which is truthfully what every page has today.
--
-- NOT NULL DEFAULT '' rather than NULL matches the eight columns already on
-- this table, so "no value" has ONE representation instead of two ('' and
-- NULL) that every reader would have to handle. Postgres 11+ records the
-- default in the catalogue instead of rewriting the table, so adding them to a
-- populated table is still a metadata-only operation.
ALTER TABLE app_content
  -- The section's own logo. A path into the same upload store as
  -- `partners.logo_path`, written by POST /api/admin/upload.
  ADD COLUMN IF NOT EXISTS logo_path        TEXT NOT NULL DEFAULT '',
  -- Kept as free text, not normalized to digits: this is a number to DISPLAY
  -- and dial, and an organization's public line may legitimately be a landline
  -- with an area code, an extension, or a short code. The app's phone
  -- normalizer exists for authenticating a mobile, which is a different job.
  ADD COLUMN IF NOT EXISTS contact_phone    TEXT NOT NULL DEFAULT '',
  -- Separate from contact_phone on purpose: the client listed them separately,
  -- and in practice a WhatsApp line is often not the office number.
  ADD COLUMN IF NOT EXISTS contact_whatsapp TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS contact_email    TEXT NOT NULL DEFAULT '',
  -- One URL per line (commas tolerated) — the exact shape partners (035) and
  -- city_directory_entries (100) store and the app already parses.
  ADD COLUMN IF NOT EXISTS social_links     TEXT NOT NULL DEFAULT '',
  -- The address is prose a human reads, so it is localized like every other
  -- text on this table. A street name transliterates differently per script.
  ADD COLUMN IF NOT EXISTS address_en       TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS address_ar       TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS address_ckb      TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS address_kmr      TEXT NOT NULL DEFAULT '';

-- NO INDEX IS ADDED HERE, DELIBERATELY.
-- Every read of these columns is `SELECT … FROM app_content WHERE slug = $1`,
-- which is the table's PRIMARY KEY lookup — already the fastest access this
-- table has. None of the nine is ever a WHERE predicate, a sort key or a join
-- column: nothing searches for a page BY its phone number. An index on any of
-- them would be dead weight paid for on every save of every content page.
--
-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- This repo's runner (internal/db/migrate.go) is forward-only and records each
-- file in schema_migrations; there is no .down.sql convention, so the reversal
-- is recorded here and was EXECUTED against a local database before this
-- migration was committed:
--
--   ALTER TABLE app_content
--     DROP COLUMN IF EXISTS logo_path,
--     DROP COLUMN IF EXISTS contact_phone,
--     DROP COLUMN IF EXISTS contact_whatsapp,
--     DROP COLUMN IF EXISTS contact_email,
--     DROP COLUMN IF EXISTS social_links,
--     DROP COLUMN IF EXISTS address_en,
--     DROP COLUMN IF EXISTS address_ar,
--     DROP COLUMN IF EXISTS address_ckb,
--     DROP COLUMN IF EXISTS address_kmr;
--   DELETE FROM schema_migrations WHERE version = '112_content_contact_fields.sql';
--
-- Reversing loses only what this migration made possible to record — the
-- contact details themselves. Nothing that existed before it is touched in
-- either direction: every page keeps its title, its body and its sub-sections.
