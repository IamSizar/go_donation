-- 064_guest_accounts.sql
-- Note #40 — real (credentialed) guest accounts.
--
-- Guests are no longer a pure client-side flag: they get an actual `users`
-- row (username + bcrypt password_hash, both columns already existed —
-- username from migration 014, password_hash from migration 006; phone was
-- already made nullable by migration 017) and a real Bearer token, so guest
-- restrictions (City Directory, messaging, purchases/service requests) can be
-- enforced server-side, not just hidden in the UI.
--
-- is_guest distinguishes a guest row from every other NULL-phone account type
-- (Google sign-in, incomplete phone/OTP signups) so RequireApproved and the
-- rest of the registration-status machinery are untouched — a guest row
-- carries registration_status='approved' (self-serve, no admin review) and
-- role_id NULL until it's upgraded (phone attached via OTP), at which point
-- is_guest flips to false and registration_status resets to 'incomplete' so
-- the account flows through the EXACT SAME registration form as any other
-- brand-new phone signup.

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_guest BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_users_is_guest ON users (is_guest) WHERE is_guest;
