-- 125 — Let a user clear notifications out of their list (client report,
-- 2026-09-16: "marking a notifcation as read doesnt make it go aweay / old
-- notifications must go away").
--
-- WHY
-- Nothing has ever removed a notification. GET /api/notifications returns
-- every row a user was ever sent, and POST /api/notifications knew one action,
-- mark_read, which flipped a flag the list did not act on. A member who has
-- used the app for a year opens a list that still holds their first week.
--
-- WHY A COLUMN AND NOT A DELETE
-- "Clear" is a per-user view decision, not a decision to destroy a record:
--   * app_notifications rows are exported by the admin export
--     (internal/handlers/admin_export.go lists both tables) and are the trail
--     behind "the member was told on the 4th";
--   * broadcast rows (user_id IS NULL) are SHARED. One user clearing an
--     announcement must not delete it from everybody else's list, so a delete
--     is not even available for half the rows.
-- So clearing stamps a time, and the list stops selecting the stamped rows.
-- Nothing is lost, and a mistake is one UPDATE away from being undone.
--
-- WHY TWO TABLES
-- A notification a user owns is theirs alone: app_notifications.cleared_at is
-- enough. A broadcast row is shared, so the per-user fact lives on the
-- per-user row that already exists for it — app_notification_reads, which is
-- keyed (notification_id, user_id) and is already where "this user has read
-- this broadcast" is recorded. A cleared broadcast is therefore a read row
-- with cleared_at set, and clearing it for one user cannot affect another.
--
-- The retention rule that hides READ rows older than 30 days needs no schema:
-- it is created_at arithmetic in notify.List (notify.ReadRetention). Unread
-- rows are never aged out — the user has not seen them yet.
--
-- ADDITIVE ONLY: two nullable columns and one partial index. No existing
-- column is changed and no row is touched — every existing row keeps
-- cleared_at NULL, which means "not cleared", which is the behaviour that was
-- there before this migration.
ALTER TABLE app_notifications
  ADD COLUMN IF NOT EXISTS cleared_at TIMESTAMP;

ALTER TABLE app_notification_reads
  ADD COLUMN IF NOT EXISTS cleared_at TIMESTAMP;

-- The list's new predicate is "this user's rows that are not cleared", which
-- is (user_id, cleared_at). Partial, because the query only ever looks for
-- rows that are NOT cleared, and a cleared row is dead weight in the index.
-- idx_app_notifications_user_read (001) still serves the read filter; this one
-- keeps the clear predicate from turning that into a filter-after-scan on a
-- member with thousands of rows.
CREATE INDEX IF NOT EXISTS idx_app_notifications_user_uncleared
  ON app_notifications (user_id)
  WHERE cleared_at IS NULL;

-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- The runner (internal/db/migrate.go) is forward-only and has no .down.sql
-- convention, so, as in 113 and 124, the reversal is recorded here. It was
-- EXECUTED against a local throwaway database before this migration was
-- committed:
--
--   DROP INDEX IF EXISTS idx_app_notifications_user_uncleared;
--   ALTER TABLE app_notification_reads DROP COLUMN IF EXISTS cleared_at;
--   ALTER TABLE app_notifications      DROP COLUMN IF EXISTS cleared_at;
--   DELETE FROM schema_migrations WHERE version = '125_notification_clearing.sql';
--
-- Reversing loses only the record of WHICH rows a user had cleared; every
-- notification itself survives, and the list goes back to showing all of them.
