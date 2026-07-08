-- 042 — Fuller sign-up profile fields (#39 grantor; reused by #40/#41). Adds
-- optional city + occupation to user_profiles (gender already exists). Nullable
-- so existing rows and the shorter eligible/volunteer forms are unaffected.
-- Idempotent.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS city       VARCHAR(120),
  ADD COLUMN IF NOT EXISTS occupation VARCHAR(160);
