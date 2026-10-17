-- 141 — campaigns.created_at, so the dashboard's campaigns list can show a
-- date/time column like every other section (client item #74).
--
-- Additive and nullable-safe: the column is added WITHOUT a default first, so
-- campaigns that already exist keep NULL ("date unknown", shown as an em dash)
-- instead of all claiming to have been created on the day this ran; the default
-- is attached afterwards so every new campaign is stamped. Idempotent.
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS created_at TIMESTAMP;
ALTER TABLE campaigns ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP;
