-- 053_volunteer_skills_translations.sql
-- The Skills free-text field on volunteer_applications (skills TEXT) had no
-- multi-language siblings, unlike description/description_ar/_sorani/_badini
-- elsewhere in this schema (see 001_full_v2.sql). Admins had no way to enter
-- a translated version, so the Volunteers table always showed the raw
-- English/whatever-language text the volunteer typed, even in Arabic mode.
-- Adds the same three sibling columns used everywhere else so admins can
-- fill in real translations per application.

ALTER TABLE volunteer_applications
  ADD COLUMN IF NOT EXISTS skills_ar TEXT,
  ADD COLUMN IF NOT EXISTS skills_sorani TEXT,
  ADD COLUMN IF NOT EXISTS skills_badini TEXT;
