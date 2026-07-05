-- 024_audit_ledger_hash.sql
--
-- Requirement 6c — make the immutable permission-change ledger tamper-EVIDENT,
-- not just append-only. Each row carries a SHA-256 chain: row_hash =
-- sha256(prev_hash || canonical(row)). Deleting or editing any row breaks every
-- subsequent row_hash, which VerifyChain() detects.
--
-- Columns are nullable so existing rows can be back-filled by the app at
-- startup (permissions.BackfillChain); new rows are always stamped on insert.
ALTER TABLE permission_audit_log
  ADD COLUMN IF NOT EXISTS prev_hash CHAR(64),
  ADD COLUMN IF NOT EXISTS row_hash  CHAR(64);
