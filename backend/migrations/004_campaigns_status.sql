-- 004_campaigns_status.sql
--
-- Phase 15.1: replace the binary `is_active` flag with a 3-value lifecycle
-- column `status` (matches the values the Flutter app's status pill already
-- understands).
--
--   active   — visible in the donor app and accepting donations
--   hidden   — not visible to donors; admin can still edit / unhide
--   finished — campaign is closed (goal reached, time expired, or admin
--              manually retired). Donors don't see it; donations are
--              rejected by the API if someone tries to POST anyway.
--
-- We keep the old `is_active` SMALLINT around for a release as a write-
-- through derived value (1 when status='active', else 0) so any external
-- script that still reads it doesn't break. New code reads `status`.

ALTER TABLE campaigns
  ADD COLUMN IF NOT EXISTS status VARCHAR(16) NOT NULL DEFAULT 'active';

-- Backfill: anything currently is_active=0 becomes 'hidden'. Everything
-- else (the default) stays 'active'.
UPDATE campaigns
   SET status = 'hidden'
 WHERE is_active = 0;

-- Hard-constrain the values so a bad PATCH can never put the column into
-- an unknown state.
ALTER TABLE campaigns
  DROP CONSTRAINT IF EXISTS campaigns_status_check;
ALTER TABLE campaigns
  ADD CONSTRAINT campaigns_status_check
    CHECK (status IN ('active', 'hidden', 'finished'));

-- Hot path: donor list does `WHERE status = 'active'` on every page load.
CREATE INDEX IF NOT EXISTS idx_campaigns_status
  ON campaigns (status);

-- The old is_active index is no longer the primary filter. Leave it for
-- legacy read-only consumers but don't depend on it.
