-- 063_phone_international.sql
-- Note #39 — international phone number support. The DB canonical form
-- changes from Iraq-only "0" + 10-digit national number (e.g. "07508582031")
-- to <country dial code><national number>, no "+", no trunk "0"
-- (e.g. "9647508582031"). This matches what auth.NormalizePhone now produces
-- and what OTPIQ's send API already expects.
--
-- This is a pure 1:1 prefix rewrite of the existing Iraq-only rows (every
-- current row matches '0' + 10 digits per migration 010's enforcement), so it
-- introduces no new collisions against the UNIQUE(phone) constraint.
--
-- Idempotent: only rows still in the old "0XXXXXXXXXX" form are touched; a
-- second run is a no-op.

UPDATE users
   SET phone = '964' || substring(phone from 2)
 WHERE phone ~ '^0\d{10}$';
