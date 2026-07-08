-- 040 — Per-user profile field privacy (#32). Stores the list of profile field
-- keys the user chose to HIDE (e.g. {'phone','address'}); an empty array means
-- everything is public. Honored wherever a profile is shown to other users.
-- Idempotent.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS field_privacy TEXT[] NOT NULL DEFAULT '{}';
