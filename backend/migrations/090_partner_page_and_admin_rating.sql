-- 090 — "Eleventh: Partners Section" — the Partner Page and the
-- administration-assessed rating.
--
-- Already present, NOT rebuilt here:
--   * Partner profile fields — name / logo_path / website / description /
--     partner_type / location / contact_phone / email / social_links, each
--     with 4-language variants where relevant (migrations 001 + 035).
--   * A 1–5 star rating — partner_ratings (one row per user) plus the
--     denormalized avg_rating / rating_count on partners, already surfaced in
--     the app with a star picker (migration 035, #27).
--   * "Future Development" — partners already has full admin CRUD (add,
--     edit, delete, status), so adding/editing/removing a partner and
--     controlling its content is a Dashboard action with no app update.
--
-- Two things the spec needs that had no schema:

-- 1. Administration-assessed rating. The existing avg_rating is a *crowd*
--    rating averaged from users; the spec asks for a level set by the
--    organization against its own criteria (completed activities, value of
--    donations, cooperation, continuity of support). Kept separate so the
--    two never overwrite each other — the app can show either or both.
ALTER TABLE partners
  ADD COLUMN IF NOT EXISTS admin_rating        NUMERIC(3,2),  -- 1.00–5.00, NULL = not assessed
  ADD COLUMN IF NOT EXISTS admin_rating_note   TEXT NOT NULL DEFAULT '',
  -- Per-criterion scores (1–5). Nullable: staff may score only some.
  ADD COLUMN IF NOT EXISTS score_activities    SMALLINT,
  ADD COLUMN IF NOT EXISTS score_donations     SMALLINT,
  ADD COLUMN IF NOT EXISTS score_cooperation   SMALLINT,
  ADD COLUMN IF NOT EXISTS score_continuity    SMALLINT;

-- Keep the assessed values inside the 1–5 range the spec defines.
ALTER TABLE partners
  ADD CONSTRAINT partners_admin_rating_range
  CHECK (admin_rating IS NULL OR (admin_rating >= 1 AND admin_rating <= 5));

-- 2. Partner attribution on activities, so the Partner Page can list
--    "history of activities or initiatives implemented in cooperation with
--    the partner". Nullable — an activity may have no partner — and ON
--    DELETE SET NULL so removing a partner never deletes its posts.
ALTER TABLE media_posts
  ADD COLUMN IF NOT EXISTS partner_id BIGINT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'media_posts_partner_fk'
  ) THEN
    ALTER TABLE media_posts
      ADD CONSTRAINT media_posts_partner_fk
      FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_media_posts_partner ON media_posts(partner_id);
