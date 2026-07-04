-- 021_guest_settings.sql
--
-- Section 27 — Guest Mode. The Primary Administrator (Super Admin) decides
-- which app screens a signed-out "guest" may browse. This table stores an
-- ON/OFF override per screen; the canonical screen list + defaults live in code
-- (internal/guest), so a missing row falls back to the code default.
--
--   screen  — canonical app-screen slug (campaigns, news, city_directory, ...).
--   enabled — whether guests can see that screen.
CREATE TABLE IF NOT EXISTS guest_settings (
  screen     VARCHAR(48) PRIMARY KEY,
  enabled    BOOLEAN     NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);
