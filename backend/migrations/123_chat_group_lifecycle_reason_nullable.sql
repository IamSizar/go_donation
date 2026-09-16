-- 123_chat_group_lifecycle_reason_nullable.sql
--
-- Make chat_group_threads.lifecycle_reason nullable, so "no reason given" is
-- NULL here exactly as it is on the four thread tables migration 118 gave a
-- lifecycle.
--
-- WHY
-- Migration 120 declared the column TEXT NOT NULL DEFAULT ''. But
-- chatlifecycle.setLifecycle, the one writer every chat system shares, stores
-- an empty reason as NULL (see its doc comment). Against this table every
-- group resume, and every group pause or end without a reason, failed with
-- SQLSTATE 23502 and reached staff as a 500 "Database error." on
-- POST /api/admin/chat-groups/:id/lifecycle. Pinned by
-- internal/chatlifecycle/apply_group_test.go.
--
-- WHY THE SCHEMA AND NOT THE WRITER
-- Writing '' for this one table would give "no reason" two spellings: NULL
-- for the donor, marriage, staff and case threads, '' for groups. Every
-- reader already handles NULL:
--   - chatlifecycle.Load scans the column into a *string;
--   - the handlers pass it through as `lifecycle_reason` (chat_lifecycle_gate.go)
--     and `reason` (admin_chat_lifecycle.go);
--   - the Flutter group conversation controller trims it and treats null and
--     "" alike, and admin-web only renders it when truthy.
-- No chatgroups query reads the column and no INSERT names it.
--
-- EXISTING ROWS
-- A group nobody has paused or ended holds ''. It becomes NULL, so an old
-- group and a new one read the same. A real reason is left alone.
-- Group rows already in the Trash (trash_items payloads) still carry "" and
-- restore as ''. Readers treat that as no reason, and the next lifecycle
-- change on the group rewrites it.
--
-- SAFETY
-- DROP NOT NULL and DROP DEFAULT change only the catalog; the table is not
-- rewritten. No Go code changes with this migration, so the running binary is
-- fixed as soon as it has been applied.

ALTER TABLE chat_group_threads
  ALTER COLUMN lifecycle_reason DROP NOT NULL,
  ALTER COLUMN lifecycle_reason DROP DEFAULT;

UPDATE chat_group_threads SET lifecycle_reason = NULL WHERE lifecycle_reason = '';

-- ─── DOWN (verified by hand against a local database) ────────────────────
-- UPDATE chat_group_threads SET lifecycle_reason = '' WHERE lifecycle_reason IS NULL;
-- ALTER TABLE chat_group_threads
--   ALTER COLUMN lifecycle_reason SET DEFAULT '',
--   ALTER COLUMN lifecycle_reason SET NOT NULL;
-- DELETE FROM schema_migrations WHERE version = '123_chat_group_lifecycle_reason_nullable.sql';
