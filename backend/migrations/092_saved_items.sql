-- 092 — "Save for later" across the app, not just marriage profiles.
--
-- marriage_saved (migration 046) already bookmarks marriage PROFILES, keyed
-- (user_id, profile_id). That shape can't hold anything else, so saving a
-- media post needed either a second single-purpose table or a generic one.
--
-- This is the generic one: (user_id, item_type, item_id). Adding "save" to
-- another kind of record later is a new item_type string, not a new table and
-- not another pair of endpoints.
--
-- marriage_saved is deliberately left in place and untouched — it works, it is
-- wired into the marriage search filter (`saved only`), and migrating it here
-- would be a data move with no user-visible benefit. Marriage keeps its own
-- bookmark list; everything else uses this one.
CREATE TABLE IF NOT EXISTS saved_items (
  user_id    INTEGER      NOT NULL,
  -- 'media_post' today. Kept as free text rather than an enum so a new kind
  -- doesn't need a migration to add.
  item_type  VARCHAR(32)  NOT NULL,
  item_id    BIGINT       NOT NULL,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, item_type, item_id)
);

-- The list query is always "this user's saves, newest first", optionally
-- narrowed to one type.
CREATE INDEX IF NOT EXISTS idx_saved_items_user
  ON saved_items (user_id, item_type, created_at DESC);
