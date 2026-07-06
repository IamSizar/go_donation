-- 027 — per-section donation-arrived SMS notifications (#15).
--
-- Each donation section (donation_kind) can have a contact phone that receives
-- a free-form SMS the moment a donor makes a donation in that section, plus an
-- on/off toggle. Admin-editable alongside the code prefix (#14) at
-- /api/admin/donation-codes. notify_phone is nullable (no phone = no SMS);
-- notify_enabled defaults on so a configured phone works out of the box.
ALTER TABLE donation_section_codes
  ADD COLUMN IF NOT EXISTS notify_phone   VARCHAR(32),
  ADD COLUMN IF NOT EXISTS notify_enabled SMALLINT NOT NULL DEFAULT 1;
