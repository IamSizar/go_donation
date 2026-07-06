-- 035 — Partners: contact/location fields (#26) + user ratings (#27).
--
-- #26 adds email, social links (one URL per line, free text), and a 4-language
--     location to the partners directory (they already had phone + website).
-- #27 adds a 1–5 star rating: a per-user partner_ratings table plus denormalized
--     avg_rating / rating_count on partners (recomputed on each submit).
--
-- All idempotent.

ALTER TABLE partners
  ADD COLUMN IF NOT EXISTS email            VARCHAR(255),
  ADD COLUMN IF NOT EXISTS social_links     TEXT,          -- one URL per line
  ADD COLUMN IF NOT EXISTS location         VARCHAR(255),
  ADD COLUMN IF NOT EXISTS location_ar      VARCHAR(255),
  ADD COLUMN IF NOT EXISTS location_sorani  VARCHAR(255),
  ADD COLUMN IF NOT EXISTS location_badini  VARCHAR(255),
  ADD COLUMN IF NOT EXISTS avg_rating       NUMERIC(3,2),  -- e.g. 4.25; NULL until first rating
  ADD COLUMN IF NOT EXISTS rating_count     INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS partner_ratings (
  partner_id BIGINT      NOT NULL,
  user_id    INTEGER     NOT NULL,
  stars      SMALLINT    NOT NULL CHECK (stars >= 1 AND stars <= 5),
  created_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (partner_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_partner_ratings_partner ON partner_ratings (partner_id);
