-- 062 — Note #37: volunteer self check-in/check-out with GPS + live photo
-- proof. Until now only STAFF could move a signup from approved→joined
-- (arrival) or joined→completion_requested (departure/done) — the volunteer
-- had no way to trigger these themselves from the app, and neither step
-- recorded any location or photo evidence for staff to verify against.
--
-- checkin_* / checkout_* are separate columns (not reused across the two
-- events) so staff can see arrival AND departure evidence side by side, even
-- though they share the existing checked_in_at / completion_requested_at
-- timestamp columns (migration 001) rather than adding redundant ones.

ALTER TABLE volunteer_mission_signups
  ADD COLUMN IF NOT EXISTS checkin_lat         DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS checkin_lng         DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS checkin_photo_path  VARCHAR(255),
  ADD COLUMN IF NOT EXISTS checkout_lat        DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS checkout_lng        DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS checkout_photo_path VARCHAR(255);
