-- 028 — donor-facing donation type (#16).
--
-- The donor now picks a giving type on the donate screen (general / zakat /
-- sadaqah). This is stored per donation, orthogonal to the internal
-- donation_kind routing (campaign/general/…). Existing rows default to
-- 'general'. The backend normalizes any incoming value to a known type.
ALTER TABLE donations
  ADD COLUMN IF NOT EXISTS donation_type VARCHAR(20) NOT NULL DEFAULT 'general';
