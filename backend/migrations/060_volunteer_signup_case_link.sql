-- 060 — volunteer-to-beneficiary-case assignment. Foundation for the
-- Staff↔Volunteer↔Beneficiary chat (Note #36, part 3): nothing in the schema
-- today links a specific volunteer to a specific beneficiary case — missions
-- are generic listings and signups only carry a status lifecycle. This adds
-- a per-signup, nullable case link (staff set it after reviewing a signup,
-- not required for missions with no specific beneficiary), same pattern
-- `sponsorships.beneficiary_case_id` already uses elsewhere in this schema.
--
-- Deliberately on the SIGNUP, not the mission: one mission can serve several
-- different beneficiaries (e.g. "weekly home visits"), and each volunteer's
-- signup should be pairable with their own case rather than every signup on
-- a mission sharing one case.

ALTER TABLE volunteer_mission_signups
  ADD COLUMN IF NOT EXISTS beneficiary_case_id BIGINT REFERENCES beneficiary_cases(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_volunteer_mission_signups_case ON volunteer_mission_signups (beneficiary_case_id);
