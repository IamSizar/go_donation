-- 049 — generic key/value app settings.
--
-- First use (#36): an admin-editable "support WhatsApp" number so staff can set
-- the AI-chat handoff number from the dashboard instead of a redeploy-only env
-- var (SUPPORT_WHATSAPP stays a fallback default). Key/value so future simple
-- settings can reuse the same table.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS + seed row ON CONFLICT DO NOTHING.
CREATE TABLE IF NOT EXISTS app_settings (
  key        VARCHAR(64) PRIMARY KEY,
  value      TEXT        NOT NULL DEFAULT '',
  updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO app_settings (key, value)
VALUES ('support_whatsapp', '')
ON CONFLICT (key) DO NOTHING;
