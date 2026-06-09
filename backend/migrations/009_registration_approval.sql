-- 009_registration_approval.sql
-- New-user registration approval flow.
--
-- New signups (created via OTP / phone login) must submit a profile
-- (name, date of birth, address, role) which an admin reviews BEFORE the
-- user can enter the app. Progress is tracked on users.registration_status.
--
-- Existing users are GRANDFATHERED: the column defaults to 'approved', so
-- every pre-existing row becomes 'approved' the moment this runs. Brand-new
-- rows are inserted explicitly as 'incomplete' by the Go code
-- (users.InsertWithPhone) — the column default only ever applies to the
-- already-present rows during this migration.
--
-- Status values:
--   incomplete  - authenticated (OTP) but registration form not submitted yet
--   pending     - form submitted, awaiting admin review
--   approved    - admin approved (or grandfathered existing user) -> full access
--   rejected    - admin rejected; user may edit and re-submit (-> pending)

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS registration_status       varchar(20) NOT NULL DEFAULT 'approved',
  ADD COLUMN IF NOT EXISTS registration_submitted_at timestamp,
  ADD COLUMN IF NOT EXISTS registration_reviewed_at  timestamp,
  ADD COLUMN IF NOT EXISTS registration_reviewed_by  integer,
  ADD COLUMN IF NOT EXISTS registration_reject_reason text;

-- Guard the allowed values.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_registration_status_chk;
ALTER TABLE users
  ADD CONSTRAINT users_registration_status_chk
  CHECK (registration_status IN ('incomplete', 'pending', 'approved', 'rejected'));

-- Reviewer FK (nullable; NULL = system / not yet reviewed).
ALTER TABLE users DROP CONSTRAINT IF EXISTS fk_users_registration_reviewed_by;
ALTER TABLE users
  ADD CONSTRAINT fk_users_registration_reviewed_by
  FOREIGN KEY (registration_reviewed_by) REFERENCES users(id) ON DELETE SET NULL;

-- The admin "pending registrations" list filters on this column.
CREATE INDEX IF NOT EXISTS idx_users_registration_status ON users (registration_status);

-- Date of birth captured by the registration form ("Born"). Nullable;
-- existing profiles simply carry NULL.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS date_of_birth date;
