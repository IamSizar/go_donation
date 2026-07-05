-- 019_otp_phone_locks.sql
--
-- Section 27 — progressive OTP rate-limiting per phone number. Complements the
-- existing per-IP window (otp_ip_rate_limit) and per-phone resend cooldown:
-- when a single phone generates excessive OTP requests, it is locked for an
-- escalating duration (1st lock 2h, 2nd 6h, 3rd+ 24h).
--
--   window_start / request_count — sliding window used to detect abuse.
--   lock_level                    — how many times this phone has been locked.
--   lock_until                    — unix seconds; while > now, requests are 429.
CREATE TABLE IF NOT EXISTS otp_phone_locks (
  phone         VARCHAR(32) PRIMARY KEY,
  window_start  BIGINT      NOT NULL DEFAULT 0,
  request_count INT         NOT NULL DEFAULT 0,
  lock_level    INT         NOT NULL DEFAULT 0,
  lock_until    BIGINT      NOT NULL DEFAULT 0
);
