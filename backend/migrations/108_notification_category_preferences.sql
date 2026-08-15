-- 108 — K7: "choose which kinds of alerts you get".
--
-- THE GAP THIS CLOSES
-- users.notifications_enabled (migration 039) is a single SMALLINT, and it was
-- the ONLY notification preference in the schema: all alerts, or none. The
-- Settings screen could offer one switch and nothing finer.
--
-- WHY THIS IS A SERVER TABLE AND NOT A CLIENT SETTING
-- The push itself is composed and sent server-side (internal/notify), so a
-- filter living in the app would silence the in-app list while the phone still
-- lit up — a switch that lies. The gate has to be here, next to the send.
--
-- WHY CATEGORY AND NOT NOTIFICATION TYPE
-- There are 81 notification types. A screen with 81 switches is not a setting,
-- it is a spreadsheet. The server ALREADY derives a category from every type
-- (notify.resolveCategory), and the app ALREADY groups the Alerts tab by those
-- same six categories (notifications_screen.dart's filter chips, mirrored in
-- app_notification_model.dart). So the category is the unit the user already
-- sees and reasons about, and gating on it needs no new classification to be
-- invented or kept in sync. A type-level switch can be layered on later
-- without changing this table's meaning.
--
-- ADDITIVE
-- Two new tables. Nothing is dropped, no column changes type, and
-- users.notifications_enabled keeps working exactly as before as the master
-- switch — this only refines it. No backfill: ABSENCE OF A ROW MEANS ENABLED,
-- so every existing user keeps receiving exactly what they receive today until
-- they choose otherwise. That deliberately matches GetNotificationsEnabled's
-- existing "missing row defaults to true so nothing is silently muted" rule.

-- One row per (user, category) the user has switched OFF or explicitly back
-- ON. enabled is stored rather than assumed so a user can re-enable a category
-- and the row simply flips, keeping the write path a plain upsert.
CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id    INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category   VARCHAR(32) NOT NULL,
  enabled    BOOLEAN     NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, category)
);

-- The primary key already indexes (user_id, category), which is exactly how
-- notify.Send reads it — one point lookup per send. No further index is added:
-- there is no query that scans by category alone.

-- The catalogue the Settings screen renders, following the data-driven pattern
-- privacy_field_options (083) established: staff can retire a category from
-- the picker without a code change or an app release.
--
-- EVERY label_key BELOW ALREADY EXISTS IN ALL FOUR LOCALES (en/ar/ckb/kmr) in
-- humanitarian/lib/localization/app_translations.dart — they are the very
-- strings the Alerts tab's own category chips already use
-- (notifications_screen.dart:497-505), so this screen reads in the user's
-- language on day one and this migration adds NO new translation work.
-- Checked key by key against all four maps. A category added later should
-- reuse an existing key the same way, or go through TRANSLATION_REQUEST.md —
-- never ship invented Kurdish.
CREATE TABLE IF NOT EXISTS notification_categories (
  category      VARCHAR(32) PRIMARY KEY,
  label_key     VARCHAR(96) NOT NULL DEFAULT '',
  enabled       BOOLEAN     NOT NULL DEFAULT TRUE,
  display_order INTEGER     NOT NULL DEFAULT 0,
  updated_at    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- The six categories notify.resolveCategory can return. Order matches the
-- Alerts tab's chips so the two screens read the same way round.
INSERT INTO notification_categories (category, label_key, display_order) VALUES
  ('urgent',   'Urgent',   10),
  ('payment',  'Payment',  20),
  ('campaign', 'Campaign', 30),
  ('system',   'System',   40),
  ('reminder', 'Reminder', 50),
  ('normal',   'Normal',   60)
ON CONFLICT (category) DO NOTHING;

-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- This repo's runner (internal/db/migrate.go) is forward-only and records each
-- file in schema_migrations; there is no .down.sql convention, so the reversal
-- is recorded here and was EXECUTED against a local database before this
-- migration was committed:
--
--   DROP TABLE IF EXISTS notification_preferences;
--   DROP TABLE IF EXISTS notification_categories;
--   DELETE FROM schema_migrations WHERE version = '108_notification_category_preferences.sql';
--
-- Reversing discards the per-category choices users had saved and returns
-- everyone to the single master switch, which is the pre-migration behaviour.
-- Nothing else is affected: no existing table or column is touched, so users,
-- app_notifications and users.notifications_enabled survive a down-and-up
-- cycle unchanged.
