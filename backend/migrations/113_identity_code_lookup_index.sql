-- 113 — K21: an identity code could not be RESOLVED to the person it names.
--
-- THE GAP THIS CLOSES
-- The client asked to look up a person's donation / support history by their
-- identity code. Two things blocked it, and both were server-side:
--
--   1. The user could never see their own code. `recipient_code` (073),
--      `volunteer_code` (077) and `grantor_code` (105) live on user_profiles,
--      and the app-facing Account struct carried none of them — the
--      registration form says the code "يتم إنشاؤه تلقائياً بعد التسجيل" and
--      then never shows it.
--   2. There was nothing to query with it. /api/history builds its timeline
--      from the token's own userID and takes no code parameter.
--
-- Both are fixed in Go (internal/users, internal/handlers/extras.go). What this
-- migration adds is the INDEX that makes the new lookup an index probe instead
-- of a sequential scan of every profile on every request.
--
-- WHY AN INDEX HERE WHEN MIGRATION 105 DELIBERATELY REFUSED ONE
-- 105's reasoning was correct and still is: the STAFF SEARCH matches
-- `up.grantor_code ILIKE '%q%'`, a LEADING-wildcard predicate a btree cannot
-- serve, so an index would have been dead weight. The K21 lookup is a different
-- query — an EXACT match on a whole code, `UPPER(col) = UPPER($1)` — which is
-- precisely what a btree does serve. So this indexes the new access path
-- without contradicting the old note; the ILIKE search still scans, as it must.
--
-- UPPER() on both sides because a code is copied off a receipt or a screen by
-- hand and "er-000123" is the same code as "ER-000123". The index has to be on
-- the same expression as the predicate or it will not be used.
--
-- PARTIAL, on `<> ''`, because the column defaults to '' and most rows hold
-- exactly that: a recipient has no volunteer_code, a donor has neither. Every
-- one of those rows would otherwise sit in the index as an identical, useless
-- key. Excluding them keeps each index to the rows that can actually be found
-- by it, which is also why three narrow indexes beat one composite — a code is
-- looked up in whichever column happens to hold it, never in a combination.
--
-- ADDITIVE ONLY: three new indexes. No column added, dropped or rewritten, and
-- no data is touched in either direction.
CREATE INDEX IF NOT EXISTS idx_user_profiles_recipient_code_upper
  ON user_profiles (UPPER(recipient_code))
  WHERE recipient_code <> '';

CREATE INDEX IF NOT EXISTS idx_user_profiles_volunteer_code_upper
  ON user_profiles (UPPER(volunteer_code))
  WHERE volunteer_code <> '';

CREATE INDEX IF NOT EXISTS idx_user_profiles_grantor_code_upper
  ON user_profiles (UPPER(grantor_code))
  WHERE grantor_code <> '';

-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- This repo's runner (internal/db/migrate.go) is forward-only and records each
-- file in schema_migrations; there is no .down.sql convention, so the reversal
-- is recorded here and was EXECUTED against a local database before this
-- migration was committed:
--
--   DROP INDEX IF EXISTS idx_user_profiles_recipient_code_upper;
--   DROP INDEX IF EXISTS idx_user_profiles_volunteer_code_upper;
--   DROP INDEX IF EXISTS idx_user_profiles_grantor_code_upper;
--   DELETE FROM schema_migrations WHERE version = '113_identity_code_lookup_index.sql';
--
-- Reversing loses no data at all — an index holds nothing that is not already
-- in the table. The lookup keeps working; it just scans.
