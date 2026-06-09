-- 007_campaigns_owner.sql
--
-- Phase 23 — let donor-facing campaigns reference a beneficiary owner.
--
-- Adding `owner_user_id` unlocks two features at once:
--   1. The "Publish to donors" admin action — copy an approved
--      beneficiary_project_request into the campaigns table while
--      preserving the original submitter as the owner.
--   2. The "Donation received on your project" notification — the
--      dormant wire in handlers/donations.go:205-243 probes for this
--      exact column via information_schema and starts firing the
--      moment it exists.
--
-- NULL is allowed because the original admin-curated campaigns (Winter
-- Relief, Medical Aid, …) don't have a beneficiary owner. Notifications
-- only fire for rows where the column is populated.

ALTER TABLE campaigns
  ADD COLUMN IF NOT EXISTS owner_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL;

-- Hot path: notification helper looks up by id then reads this column. The
-- PK already covers id-lookups; we add a partial index for owner_user_id
-- to speed up future "campaigns I own" admin / mobile queries.
CREATE INDEX IF NOT EXISTS idx_campaigns_owner
  ON campaigns (owner_user_id) WHERE owner_user_id IS NOT NULL;
