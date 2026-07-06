-- 026 — per-section transaction-code namespaces (#14).
--
-- Each donation section (donation_kind) gets its own code prefix and an
-- independent running sequence, so reference numbers read like CAM-000042 /
-- INK-000007 instead of one shared global DON- pool. The prefix is admin-
-- editable via /api/admin/donation-codes; next_seq is bumped atomically as
-- each donation is created. Existing DON-… codes are left untouched.
CREATE TABLE IF NOT EXISTS donation_section_codes (
  kind       VARCHAR(20) PRIMARY KEY,
  prefix     VARCHAR(16) NOT NULL,
  next_seq   BIGINT      NOT NULL DEFAULT 1,
  updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by BIGINT
);

-- Seed the five fixed donation kinds with sensible default prefixes. Idempotent:
-- re-running the migration (or seeding a kind that already exists) is a no-op.
INSERT INTO donation_section_codes (kind, prefix) VALUES
  ('general',     'GEN'),
  ('campaign',    'CAM'),
  ('sponsorship', 'SPN'),
  ('in_kind',     'INK'),
  ('operational', 'OPS')
ON CONFLICT (kind) DO NOTHING;
