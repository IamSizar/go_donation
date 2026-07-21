-- 055 — Note 31: per-employee (not just per-tier) sidebar/section access.
-- Until now role_permissions only stored TIER-wide overrides — two employees
-- on the same tier were always permission-identical. This adds an optional
-- user_id: when set, the row is a per-user override that wins over the
-- tier's own override/default for that (user, module, action). tier stays
-- NOT NULL on user-scoped rows too (informational — records what tier the
-- user was on on write, for the audit trail), but user-scoped resolution
-- looks up by user_id only, never by tier.
--
-- The old UNIQUE(tier, module, action) can't apply once user_id exists (a
-- given tier may now have many per-user rows with unrelated (module,action)
-- pairs) — replaced with two partial unique indexes so each kind of row
-- still can't be duplicated.

ALTER TABLE role_permissions
  ADD COLUMN IF NOT EXISTS user_id INTEGER REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE role_permissions DROP CONSTRAINT IF EXISTS role_permissions_tier_module_action_key;

CREATE UNIQUE INDEX IF NOT EXISTS role_permissions_tier_uniq
  ON role_permissions (tier, module, action) WHERE user_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS role_permissions_user_uniq
  ON role_permissions (user_id, module, action) WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_role_permissions_user ON role_permissions (user_id) WHERE user_id IS NOT NULL;
