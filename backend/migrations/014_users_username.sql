-- 014_users_username.sql
--
-- Phase 30 — username-based admin login for the dashboard.
--
--   • Adds an optional `username` so admins can sign in with username +
--     password instead of the hardcoded phone. Regular phone/OTP users keep
--     username NULL and are unaffected.
--   • Partial UNIQUE index allows many NULLs but enforces uniqueness when a
--     username is set.

ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(64);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username
  ON users (username)
  WHERE username IS NOT NULL;
