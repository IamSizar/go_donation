-- 033 — Media post location + media gallery (#23).
--
-- Adds two things to media_posts:
--   * location (4-language text) — where the activity/news took place. Text,
--     not lat/lng, matching the beneficiary_project_requests.location pattern.
--   * gallery (text[]) — additional images beyond the single media_url hero,
--     so a post can show a photo gallery. Each entry is a relative upload path
--     (images/uploads/<x>.jpg) or an absolute URL; the app resolves both.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS.
ALTER TABLE media_posts
  ADD COLUMN IF NOT EXISTS location         VARCHAR(255),
  ADD COLUMN IF NOT EXISTS location_ar      VARCHAR(255),
  ADD COLUMN IF NOT EXISTS location_sorani  VARCHAR(255),
  ADD COLUMN IF NOT EXISTS location_badini  VARCHAR(255),
  ADD COLUMN IF NOT EXISTS gallery          TEXT[] NOT NULL DEFAULT '{}';
