-- 106 — F7: قائمة المهام could not be grouped into sections or reordered.
--
-- THE GAP THIS CLOSES
-- F7 asks for four things on Dashboard → المتطوعين → قائمة المهام: add a
-- mission, edit one, CHANGE ITS SECTION, and REORDER them. Add/edit/delete and
-- status already worked. The last two could not be built at all, because
-- `volunteer_missions` (001_full_v2.sql:691-709) had **no column to store a
-- section in and no column to sort by** — verified across every migration from
-- 002 to 105, none of which adds one. The list was therefore hard-ordered by
-- `ORDER BY m.id DESC` (admin_lists.go), i.e. newest first, with no way for
-- staff to influence it.
--
-- ADDITIVE ONLY
-- Two new columns with safe defaults. Nothing dropped, no type changed, no
-- existing value rewritten, and no backfill — every existing mission keeps its
-- current meaning:
--
--   section       = ''  → "not filed under any section", which is exactly what
--                        every mission is today. The dashboard groups the
--                        unsectioned ones together rather than hiding them.
--   display_order = 0   → all equal, so the existing `id DESC` tiebreak keeps
--                        today's newest-first order until staff actually drag
--                        something. Ordering by (display_order, id DESC) with
--                        every row at 0 reproduces the current list exactly.
--
-- `section` is free text rather than a foreign key to a sections table on
-- purpose. The client asked to "change their sections", not to manage a
-- section catalogue, and a second admin-managed CMS table would be a bigger
-- guess than the note supports. If sections later need their own names in four
-- languages, promoting this column to a FK is a follow-up migration — and that
-- is why it is TEXT NOT NULL DEFAULT '' rather than a CHECK-constrained enum,
-- so the promotion does not require a destructive change.
ALTER TABLE volunteer_missions
  ADD COLUMN IF NOT EXISTS section       TEXT    NOT NULL DEFAULT '';
ALTER TABLE volunteer_missions
  ADD COLUMN IF NOT EXISTS display_order INTEGER NOT NULL DEFAULT 0;

-- Index justification — the admin list becomes
--   SELECT … FROM volunteer_missions m … ORDER BY m.display_order, m.id DESC
-- on every page load of قائمة المهام, so (display_order, id) is the new sort
-- key and this index removes that sort. `id DESC` still reads from the same
-- index (Postgres scans a btree backwards for a mixed-direction request on a
-- trailing column), so one index covers the whole ORDER BY.
--
-- No index on `section`: it is displayed and grouped in the client, never used
-- as a WHERE predicate by any query added here, and the table is small enough
-- that an unused index would only cost writes. Add one when a filter-by-section
-- query actually exists.
CREATE INDEX IF NOT EXISTS idx_volunteer_missions_order
  ON volunteer_missions (display_order, id);

-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- This repo's runner (internal/db/migrate.go) is forward-only and records each
-- file in schema_migrations; there is no .down.sql convention, so the reversal
-- is recorded here and was EXECUTED against a local database before this
-- migration was committed:
--
--   DROP INDEX IF EXISTS idx_volunteer_missions_order;
--   ALTER TABLE volunteer_missions DROP COLUMN IF EXISTS display_order;
--   ALTER TABLE volunteer_missions DROP COLUMN IF EXISTS section;
--   DELETE FROM schema_migrations WHERE version = '106_mission_section_and_order.sql';
--
-- Reversing loses only what this migration made possible to record — the
-- section names and the hand-picked order. Every mission itself, and every
-- column that existed before, is untouched by both directions.
