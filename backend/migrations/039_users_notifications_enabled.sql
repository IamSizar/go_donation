-- 039 — Per-user notification switch (#31). Users can turn notifications off in
-- settings; when off, notify.Send skips them (no in-app row, no push).
-- Defaults to enabled so existing users are unaffected. Idempotent.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS notifications_enabled SMALLINT NOT NULL DEFAULT 1;
