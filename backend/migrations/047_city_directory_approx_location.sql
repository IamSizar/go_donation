-- 047 — Approximate location for privacy (#48). When approx_location=1, the
-- public City Guide API returns coordinates snapped to a ~500m grid so the
-- exact spot is never exposed to app users. Admins still see/edit exact coords.
-- Default 0 (exact). Idempotent.
ALTER TABLE city_directory_entries
  ADD COLUMN IF NOT EXISTS approx_location SMALLINT NOT NULL DEFAULT 0;
