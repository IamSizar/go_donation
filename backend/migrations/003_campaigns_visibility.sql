-- 003_campaigns_visibility.sql
--
-- Phase 15: unify donor and admin campaign views on the `campaigns` table.
-- Previously the donor app (/api/campaigns) read from `beneficiary_project_requests`
-- while the admin (/api/admin/campaigns) read from `campaigns`. Those tables
-- never shared rows so admin-managed campaigns were invisible to donors.
--
-- This migration adds a visibility flag so admins can publish/hide a campaign
-- on the donor side without deleting the row. Existing seeded rows default to
-- visible (1) so the donor app immediately starts seeing the 4 admin campaigns
-- on the next request.

ALTER TABLE campaigns
  ADD COLUMN IF NOT EXISTS is_active SMALLINT NOT NULL DEFAULT 1;

-- Index for the hot path: donor list queries always filter `WHERE is_active = 1`.
CREATE INDEX IF NOT EXISTS idx_campaigns_is_active
  ON campaigns (is_active);
