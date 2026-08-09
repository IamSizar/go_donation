-- 095 — One task assigned to several people at once (#5).
--
-- The shape stays "one row per person". The alternative — one task row plus a
-- task_assignees join table — would have meant reworking every existing query
-- and the app's own list, and it buys nothing here: completion is already
-- per-person (each assignee marks their own copy done, migration 066), and
-- that is exactly what the client asked for. Grouping is presentation.
--
-- So a batch assignment inserts N rows sharing one group_id, and the admin
-- list collapses them back into a single card showing "3 of 5 done".
CREATE SEQUENCE IF NOT EXISTS task_group_seq;

ALTER TABLE tasks
  -- NULL means "assigned on its own", which is every row created before this
  -- migration. The admin list treats such a row as a group of one rather than
  -- backfilling ids that would carry no information.
  ADD COLUMN IF NOT EXISTS group_id BIGINT;

-- The admin list pages over groups and then fetches their rows, so both the
-- lookup by group and the "newest group first" ordering go through this.
CREATE INDEX IF NOT EXISTS idx_tasks_group ON tasks (group_id, id DESC);
