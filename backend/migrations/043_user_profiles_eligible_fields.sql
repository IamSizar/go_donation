-- 043 — Eligible (beneficiary) sign-up fields (#40). Added to user_profiles so
-- the shared registration write path persists them; only the eligible form
-- fills them in. All nullable/optional. Idempotent.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS family_size    INTEGER,
  ADD COLUMN IF NOT EXISTS housing_status VARCHAR(40),
  ADD COLUMN IF NOT EXISTS monthly_income VARCHAR(60);
