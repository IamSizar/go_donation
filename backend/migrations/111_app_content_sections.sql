-- 111 — K12: من نحن was one free-text blob, with no way to give it named parts.
--
-- THE GAP THIS CLOSES
-- The client asked for "About Us" to carry THREE NAMED sub-sections (about the
-- app, about the organization, about its goals) and to stay EXTENDABLE — more
-- sub-sections later, without a code change.
--
-- `app_content` (migration 025) stores exactly one title and one body per
-- locale per page, and nothing else; verified against every migration from 026
-- to 110, none of which adds a second body or any ordering column. The app
-- renders precisely those two fields
-- (humanitarian/lib/modules/legal/screens/content_page_screen.dart:90-118), so
-- there was no field to put a second sub-section IN, let alone a third, and no
-- column to order them by. This migration builds that structure. It seeds NO
-- prose: the owner supplies the actual text later, from the dashboard.
--
-- THE CONTRACT THIS ESTABLISHES
--   * A page with ZERO sections behaves exactly as it does today — `body_*` is
--     the page, and the plain body editor is what writes it.
--   * A page WITH sections is composed FROM those sections: saving the section
--     list rewrites `app_content.body_*` by concatenating the sections in
--     order (internal/content/content.go, ReplaceSections).
--
-- The second rule is what keeps this from shipping dark. The Flutter screen
-- reads `body_*` and cannot be changed from this side of the repo, so deriving
-- the blob is what makes a three-sub-section About Us visible in the app that
-- is already installed, while `sections` in the same API response is what a
-- future app build renders as real, separately-titled blocks.
--
-- ADDITIVE ONLY
-- One new table and one new index. No column is dropped, no type changed, and
-- the backfill below only ever WRITES rows that did not exist.
CREATE TABLE IF NOT EXISTS app_content_sections (
  id            BIGSERIAL PRIMARY KEY,
  -- FK to the page this sub-section belongs to. CASCADE because a sub-section
  -- has no meaning without its page; there is no delete path for app_content
  -- today, so this is a safety net rather than a used code path.
  slug          VARCHAR(48) NOT NULL REFERENCES app_content(slug) ON DELETE CASCADE,
  -- Sort key. Staff reorder by rewriting these, so gaps and ties are legal;
  -- `id` breaks a tie so the order is always total and always stable.
  display_order INTEGER     NOT NULL DEFAULT 0,
  -- The sub-section's NAME, per locale. Empty is legal and meaningful: it is
  -- an untitled block of prose, which is what every page holds today.
  title_en      TEXT        NOT NULL DEFAULT '',
  title_ar      TEXT        NOT NULL DEFAULT '',
  title_ckb     TEXT        NOT NULL DEFAULT '',
  title_kmr     TEXT        NOT NULL DEFAULT '',
  body_en       TEXT        NOT NULL DEFAULT '',
  body_ar       TEXT        NOT NULL DEFAULT '',
  body_ckb      TEXT        NOT NULL DEFAULT '',
  body_kmr      TEXT        NOT NULL DEFAULT '',
  created_at    TIMESTAMP   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMP   NOT NULL DEFAULT NOW(),
  updated_by    BIGINT
);

-- Index justification — every read of this table is
--   SELECT … FROM app_content_sections WHERE slug = $1 ORDER BY display_order, id
-- (public GET /api/content/:slug, and the dashboard editor), so `slug` is the
-- only WHERE predicate and (display_order, id) is the only ORDER BY. One index
-- covering all three serves the filter and removes the sort in a single scan.
-- No other index is added: no query here filters or sorts on anything else,
-- and an unused index would only be paid for on every save.
CREATE INDEX IF NOT EXISTS idx_app_content_sections_slug_order
  ON app_content_sections (slug, display_order, id);

-- BACKFILL — move every existing page's blob into its first sub-section.
--
-- Without this, the first time staff opened the sub-section editor on a page
-- they would see an EMPTY list next to text they could no longer edit, and the
-- first save would compose the page out of nothing and blank it. Copying the
-- blob in as sub-section #1 means the very first save reproduces today's page
-- byte for byte.
--
-- The section's TITLE is left empty on purpose. The page already renders
-- `app_content.title_*` as its heading, so repeating it as a sub-section name
-- would double it — and inventing names for the owner's three sub-sections is
-- exactly what this migration must not do. With an empty title the composed
-- body is the body it was copied from, unchanged.
--
-- Applies to every page, not just 'about': the editor is one shared component
-- across all eight pages, so any page staff open must already hold its own text
-- as a sub-section. Guarded to add only where nothing exists — a page that
-- somehow already has sections is left exactly as it is, so re-running is a
-- no-op.
INSERT INTO app_content_sections
  (slug, display_order, body_en, body_ar, body_ckb, body_kmr)
SELECT c.slug, 0, c.body_en, c.body_ar, c.body_ckb, c.body_kmr
  FROM app_content c
 WHERE NOT EXISTS (
         SELECT 1 FROM app_content_sections s WHERE s.slug = c.slug
       );

-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- This repo's runner (internal/db/migrate.go) is forward-only and records each
-- file in schema_migrations; there is no .down.sql convention, so the reversal
-- is recorded here and was EXECUTED against a local database before this
-- migration was committed:
--
--   DROP TABLE IF EXISTS app_content_sections;
--   DELETE FROM schema_migrations WHERE version = '111_app_content_sections.sql';
--
-- Reversing loses only what this migration made possible to record — the
-- sub-section split and its order. Nothing that existed before it is touched
-- in either direction: `app_content` keeps every column and, because the
-- composed body is written back into `body_*`, the page text survives the
-- reversal in the same field the app has always read it from.
