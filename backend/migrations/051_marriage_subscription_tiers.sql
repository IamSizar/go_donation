-- 051_marriage_subscription_tiers.sql
--
-- Note #17 — the "Free" subscription_status shown on Marriage profiles was
-- misleading: the service isn't free, only its search feature is. Replaces
-- the old free/paid/waived enum with 5 real package tiers:
--   bronze / silver / gold / diamond / vip
--
-- Per the client: bronze IS the old "free" tier (entry-level, search-only).
-- Existing rows also default to bronze regardless of their old value —
-- there's no historical data distinguishing which paid tier a 'paid'/'waived'
-- profile was actually on, so bronze is the safe fallback; staff can
-- reassign individual profiles to a real paid tier afterward via the
-- existing subscription dropdown.
--
-- The constraint name 'marriage_profiles_subscription_status_check' is
-- Postgres's auto-generated name for the unnamed column-level CHECK created
-- in migration 001 (confirmed via \d marriage_profiles).

ALTER TABLE marriage_profiles DROP CONSTRAINT IF EXISTS marriage_profiles_subscription_status_check;

UPDATE marriage_profiles SET subscription_status = 'bronze'
 WHERE subscription_status IN ('free', 'paid', 'waived');

ALTER TABLE marriage_profiles ALTER COLUMN subscription_status SET DEFAULT 'bronze';

ALTER TABLE marriage_profiles ADD CONSTRAINT marriage_profiles_subscription_status_check
  CHECK (subscription_status IN ('bronze', 'silver', 'gold', 'diamond', 'vip'));

-- Admin-configurable price per package tier (Note #17 second half — "admin
-- can set the package prices"). Reuses the generic app_settings key/value
-- store (internal/appsettings) rather than a new table — one row per tier,
-- keyed "marriage_package_price_<tier>", value = price in IQD as text.
-- Seeded at 0 so GetMarriagePackagePrices never has to guess a default.
INSERT INTO app_settings (key, value) VALUES
  ('marriage_package_price_bronze', '0'),
  ('marriage_package_price_silver', '0'),
  ('marriage_package_price_gold', '0'),
  ('marriage_package_price_diamond', '0'),
  ('marriage_package_price_vip', '0')
ON CONFLICT (key) DO NOTHING;
