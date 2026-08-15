-- 105 — H23: the donor was the one role with no identity code.
--
-- THE GAP THIS CLOSES
-- H23 asks for auto-generated identity codes "instead of real names" for
-- donors AND beneficiaries, so a person can be referred to without exposing
-- who they are. Two of the three roles already had one:
--
--   role 2, eligible recipient -> recipient_code ER-%06d  (migration 073)
--   role 3, volunteer          -> volunteer_code VL-%06d  (migration 077)
--   role 1, grantor / donor    -> nothing
--
-- So the role the client named first was the only one still identified solely
-- by name and phone number. The staff search made it concrete: it matches
-- recipient_code and volunteer_code, so an ER-/VL- code finds a person while a
-- donor could only be found by typing their real name.
--
-- The prefix is GR-, for Grantor, which is the English noun this project
-- settled on for role 1 (HANDOFF §3.5 / TERMINOLOGY T2, "Donor -> Grantor /
-- المانح"). Checked for collisions before choosing it: the codes already in
-- use are ER-, VL-, MARR- and the nine donation-section prefixes
-- (ACH CAM GEN INK MRG OPS PRD PRJ SPN). GR- is unused.
--
-- ADDITIVE
-- One new column with a safe default, exactly mirroring its two siblings, plus
-- a backfill that only ever WRITES a code where there was none. No column is
-- dropped, no type changed, and no existing value is overwritten.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS grantor_code TEXT NOT NULL DEFAULT '';

-- Backfill the donors who registered before this migration. Without it the
-- feature would only exist for people who sign up from now on, which does not
-- answer the client's ask for the accounts already in the system.
--
-- This ADDS information and can lose none: the WHERE clause restricts it to
-- rows whose code is still empty, so a code assigned by any other path (or by
-- hand) is left exactly as it is. LPAD(...,6,'0') reproduces the Go format
-- verb %06d used by ER- and VL-, so a backfilled code and a freshly assigned
-- one are indistinguishable.
UPDATE user_profiles p
   SET grantor_code = 'GR-' || LPAD(p.user_id::text, 6, '0')
  FROM users u
 WHERE u.id = p.user_id
   AND u.role_id = 1
   AND p.grantor_code = '';

-- NO INDEX IS ADDED HERE, DELIBERATELY.
-- The rule is to index frequent WHERE columns, and this column is read by the
-- staff search — but that search is `up.grantor_code ILIKE '%q%'`
-- (internal/users/users.go), a LEADING-wildcard match, which a btree index
-- cannot serve. An index would be dead weight paid for on every profile write.
-- Its two siblings, recipient_code (073) and volunteer_code (077), are
-- unindexed for the same reason, and this column is queried identically.
-- If that search ever becomes slow, the fix is a pg_trgm GIN index across all
-- three code columns at once, not a btree on this one.
--
-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- This repo's runner (internal/db/migrate.go) is forward-only and records each
-- file in schema_migrations; there is no .down.sql convention, so the reversal
-- is recorded here and was EXECUTED against a local database before this
-- migration was committed:
--
--   ALTER TABLE user_profiles DROP COLUMN IF EXISTS grantor_code;
--   DELETE FROM schema_migrations WHERE version = '105_grantor_identity_code.sql';
--
-- Reversing drops the generated codes. That is lossless for user-authored
-- data — every value in this column is derived from user_id, so re-applying
-- the migration regenerates exactly the same codes — but note that any code an
-- operator had edited BY HAND would not come back, and re-applying would give
-- that donor the derived GR- code instead.
