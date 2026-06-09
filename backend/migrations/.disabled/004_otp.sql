-- OTP state persistence (in PHP this lived in $_SESSION; in Go we use the DB
-- so the OTP flow works statelessly across HTTP requests).

CREATE TABLE IF NOT EXISTS otp_codes (
  phone       VARCHAR(64) PRIMARY KEY,
  code_hash   VARCHAR(255) NOT NULL,
  mode        VARCHAR(16)  NOT NULL DEFAULT 'real'
                CHECK (mode IN ('real','demo')),
  attempts    INTEGER      NOT NULL DEFAULT 0,
  sent_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at  TIMESTAMP    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_otp_codes_expires ON otp_codes(expires_at);

CREATE TABLE IF NOT EXISTS otp_ip_rate_limit (
  ip_address     VARCHAR(45) PRIMARY KEY,
  window_start   BIGINT      NOT NULL,
  request_count  INTEGER     NOT NULL DEFAULT 0
);
