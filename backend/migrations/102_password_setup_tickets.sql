-- 102_password_setup_tickets.sql
--
-- A16 — the owner's decided design: "OTP for account creation only, password
-- will be used for sign in to the app later."
--
-- That splits sign-up into two requests — verify the number, then choose a
-- password — and something has to carry "this number answered a code" between
-- them. Nothing could: the OTP record is DELETED on a successful verify, so a
-- verified factor left no durable trace at all (see the A16 note in
-- CLIENT_NOTES_CHECKLIST.md). This table is that trace.
--
--   phone       — the number that answered the code. One live claim per number:
--                 re-verifying replaces the row rather than adding a second.
--   ticket_hash — SHA-256 of a 256-bit random ticket. The plaintext is returned
--                 to the caller once and never stored. SHA-256 rather than
--                 bcrypt because the ticket is random, not human-chosen — see
--                 internal/auth/password_setup.go for the reasoning.
--   attempts    — wrong tickets submitted against this phone; capped at 5, the
--                 same ceiling OTP codes get.
--   expires_at  — ten minutes after issue.
--
-- A ticket authorises exactly ONE thing: giving a password to an account that
-- has none. It is not a session, it cannot reset an existing password, and it
-- cannot be replayed — /api/auth/password/set deletes the row as it spends it.
--
-- REVERSAL: DROP TABLE password_setup_tickets. Nothing references it by foreign
-- key and no other table's rows depend on it, so dropping it only closes the
-- set-a-password flow; every existing account and session is untouched.

CREATE TABLE IF NOT EXISTS password_setup_tickets (
  phone       VARCHAR(64)  PRIMARY KEY,
  ticket_hash VARCHAR(64)  NOT NULL,
  attempts    INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ  NOT NULL
);

-- Expired tickets are refused on read and deleted as they are found; the index
-- is here so a future sweep of dead rows does not have to scan the table.
CREATE INDEX IF NOT EXISTS idx_password_setup_tickets_expires
  ON password_setup_tickets (expires_at);
