-- 018_account_status.sql
--
-- Section 25 — Immediate Administrative Actions. A user account gains a
-- lifecycle status distinct from the boolean `active` flag so the Primary
-- Administrator can Temporarily Suspend or Permanently Ban an account (not just
-- deactivate it):
--
--   active    — normal.
--   suspended — temporary block; can be lifted back to active.
--   banned    — permanent block.
--
-- Enforcement: auth.ResolveToken treats 'suspended'/'banned' as an invalid
-- session (every authenticated request — dashboard AND mobile — is denied),
-- and the admin action also revokes the account's live tokens (force logout).
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS account_status VARCHAR(20) NOT NULL DEFAULT 'active';

CREATE INDEX IF NOT EXISTS idx_users_account_status ON users (account_status);
