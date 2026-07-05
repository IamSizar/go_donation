-- 023_login_attempts.sql
--
-- Requirement 6c — login brute-force throttle. Mirrors otp_phone_locks
-- (migration 019): a sliding window of failed password attempts per identity,
-- with an escalating lock once the threshold is crossed.
--
-- `identifier` is namespaced so phone-login and admin-username-login share one
-- table without colliding:  'p:<canonical_phone>'  or  'u:<username>'.
CREATE TABLE IF NOT EXISTS login_attempts (
  identifier    VARCHAR(160) PRIMARY KEY,
  window_start  BIGINT       NOT NULL DEFAULT 0,
  fail_count    INT          NOT NULL DEFAULT 0,
  lock_level    INT          NOT NULL DEFAULT 0,
  lock_until    BIGINT       NOT NULL DEFAULT 0
);
