-- 006_users_password_hash.sql
--
-- Phase 20 — add optional password authentication for admins.
--
-- Behavior:
--   • users.password_hash is NULL by default — existing rows keep working
--     with the phone-only login flow.
--   • When a row HAS a password_hash, /api/auth/login REQUIRES the caller
--     to submit a matching password — phone-only login is rejected for
--     password-protected accounts.
--   • Hashes are bcrypt (golang.org/x/crypto/bcrypt) — same library the
--     OTP store uses for the code hashes.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
