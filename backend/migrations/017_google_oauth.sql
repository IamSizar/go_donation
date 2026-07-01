-- 017_google_oauth.sql — Phase 9 (B-09): Google OAuth sign-in.
--
-- Google users may have no phone number, so phone becomes optional. We add a
-- google_sub (the stable Google account id) and email so we can find-or-create
-- and link accounts. Both get partial-unique indexes (NULLs allowed for the
-- existing phone-only users).

ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

ALTER TABLE users ADD COLUMN IF NOT EXISTS email      VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_sub VARCHAR(255);

-- One account per Google subject; one account per email. Partial so the many
-- existing rows with NULL email/google_sub don't collide.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_sub
    ON users (google_sub) WHERE google_sub IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique
    ON users (email) WHERE email IS NOT NULL;
