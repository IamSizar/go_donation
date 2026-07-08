-- 044 — Volunteer/employee sign-up fields (#41). Added to user_profiles so the
-- shared registration write path persists them; only the volunteer form fills
-- them in. All nullable/optional. Idempotent.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS skills       TEXT,
  ADD COLUMN IF NOT EXISTS availability VARCHAR(120),
  ADD COLUMN IF NOT EXISTS experience   VARCHAR(40);
