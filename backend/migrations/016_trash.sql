-- 016_trash.sql — Phase 7 (G-06 / A-16): a central Trash container.
--
-- Instead of hard-deleting admin records, deletes now copy the whole row into
-- trash_items as a JSON "document" and remove it from its source table. A
-- Super-Admin can later restore it (re-insert from the payload) or permanently
-- purge it (PIN-gated). This keeps a single, uniform recovery point for every
-- module without adding a deleted_at column to ~20 tables.

CREATE TABLE IF NOT EXISTS trash_items (
    id            BIGSERIAL PRIMARY KEY,
    source_table  VARCHAR(64) NOT NULL,     -- the table the row came from
    row_id        BIGINT      NOT NULL,     -- its primary key at delete time
    payload       JSONB       NOT NULL,     -- the full row (to_jsonb) for restore
    deleted_by    BIGINT,                   -- users.id of the admin who deleted it
    deleted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    restored_at   TIMESTAMPTZ              -- set when restored; NULL = still in trash
);

-- Fast listing of what's currently in the trash (not yet restored), newest first.
CREATE INDEX IF NOT EXISTS idx_trash_items_active
    ON trash_items (deleted_at DESC)
    WHERE restored_at IS NULL;

-- Lookups by origin (e.g. "is this row already trashed?").
CREATE INDEX IF NOT EXISTS idx_trash_items_source
    ON trash_items (source_table, row_id);
