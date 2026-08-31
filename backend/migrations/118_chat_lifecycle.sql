-- 118_chat_lifecycle.sql
--
-- Give EVERY chat in the product a staff-controlled lifecycle: END, PAUSE
-- (+ resume), ARCHIVE (+ un-archive) and DELETE-to-Trash. Four separate chat
-- systems exist and all four get the same columns, so "ended" means one thing
-- everywhere:
--
--   chat_threads                 (012) — donor ↔ campaign owner
--   marriage_chat_threads        (058) — staff-mediated marriage introduction
--   staff_chat_threads           (059) — staff ↔ staff, internal
--   case_volunteer_chat_threads  (061) — staff ↔ volunteer ↔ beneficiary
--
-- WHY A NEW COLUMN INSTEAD OF REUSING `status`
-- Two of the four already have `status`, and it does NOT mean "lifecycle" —
-- it is the CONSENT handshake: 'pending' (the other party has not accepted
-- yet) → 'active' → 'declined'. Overloading it with 'paused'/'ended' would
-- silently redefine every existing read of it (accept/decline flows, the
-- "incoming_pending" badge, the admin list filters) and would make an ended
-- thread indistinguishable from a declined invitation. `lifecycle` is
-- therefore additive and orthogonal: a thread must be BOTH consented
-- (status = 'active', where that concept exists) AND lifecycle = 'open'
-- before anybody may post into it.
--
-- WHY ARCHIVE IS A SEPARATE COLUMN, NOT A `lifecycle` VALUE
-- Archive answers "can the participants SEE this thread?", while
-- open/paused/ended answers "may anybody SEND into it?". They are
-- independent: staff archive an ended thread to clear it out of the users'
-- inboxes, and un-archiving must put it back exactly as it was — which is
-- impossible if archiving overwrote the state it needs to return to.
-- archived_at NULL = visible to the participants; NOT NULL = hidden from
-- them (staff keep seeing it on the dashboard).
--
-- Archiving is deliberately a STAFF MODERATION action, not a per-user tidy-up:
-- there is one flag per THREAD, not one per participant, because the owner's
-- requirement is "archive from dashboard, hides it from users".
--
-- REVERSIBILITY
-- This repo runs migrations forward-only (internal/db.RunMigrations, no .down
-- files anywhere in migrations/). The exact inverse is recorded at the bottom
-- of this file and was executed against a local database before committing.

-- ─── chat_threads (012) — donor ↔ campaign owner ─────────────────────────
ALTER TABLE chat_threads
  ADD COLUMN IF NOT EXISTS lifecycle VARCHAR(16) NOT NULL DEFAULT 'open',
  -- Why the thread was paused or ended, in the staff member's own words. Shown
  -- verbatim to BOTH participants in place of the composer, so "you can't send
  -- messages here" always says why. NULL = no reason given.
  ADD COLUMN IF NOT EXISTS lifecycle_reason TEXT,
  ADD COLUMN IF NOT EXISTS lifecycle_changed_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS lifecycle_changed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS archived_by INTEGER REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE chat_threads DROP CONSTRAINT IF EXISTS chk_chat_threads_lifecycle;
ALTER TABLE chat_threads
  ADD CONSTRAINT chk_chat_threads_lifecycle
  CHECK (lifecycle IN ('open','paused','ended'));

-- Partial index: the participant-facing list filters on `archived_at IS NULL`
-- on every load, and archived threads are the rare minority, so indexing only
-- the archived rows keeps the index tiny while still answering the negation.
CREATE INDEX IF NOT EXISTS idx_chat_threads_archived
  ON chat_threads (archived_at) WHERE archived_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_threads_lifecycle
  ON chat_threads (lifecycle) WHERE lifecycle <> 'open';

-- ─── marriage_chat_threads (058) — staff-mediated introduction ───────────
-- This chat is already staff-mediated by design (staff approve the meeting
-- request that opens it), so a staff-only lifecycle is the same authority it
-- already has, applied to the other end of the conversation.
ALTER TABLE marriage_chat_threads
  ADD COLUMN IF NOT EXISTS lifecycle VARCHAR(16) NOT NULL DEFAULT 'open',
  ADD COLUMN IF NOT EXISTS lifecycle_reason TEXT,
  ADD COLUMN IF NOT EXISTS lifecycle_changed_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS lifecycle_changed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS archived_by INTEGER REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE marriage_chat_threads DROP CONSTRAINT IF EXISTS chk_marriage_chat_threads_lifecycle;
ALTER TABLE marriage_chat_threads
  ADD CONSTRAINT chk_marriage_chat_threads_lifecycle
  CHECK (lifecycle IN ('open','paused','ended'));

CREATE INDEX IF NOT EXISTS idx_marriage_chat_threads_archived
  ON marriage_chat_threads (archived_at) WHERE archived_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_marriage_chat_threads_lifecycle
  ON marriage_chat_threads (lifecycle) WHERE lifecycle <> 'open';

-- ─── staff_chat_threads (059) — internal staff ↔ staff ───────────────────
-- Had NO state column at all: a staff chat could only ever exist or not.
ALTER TABLE staff_chat_threads
  ADD COLUMN IF NOT EXISTS lifecycle VARCHAR(16) NOT NULL DEFAULT 'open',
  ADD COLUMN IF NOT EXISTS lifecycle_reason TEXT,
  ADD COLUMN IF NOT EXISTS lifecycle_changed_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS lifecycle_changed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS archived_by INTEGER REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE staff_chat_threads DROP CONSTRAINT IF EXISTS chk_staff_chat_threads_lifecycle;
ALTER TABLE staff_chat_threads
  ADD CONSTRAINT chk_staff_chat_threads_lifecycle
  CHECK (lifecycle IN ('open','paused','ended'));

CREATE INDEX IF NOT EXISTS idx_staff_chat_threads_archived
  ON staff_chat_threads (archived_at) WHERE archived_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_staff_chat_threads_lifecycle
  ON staff_chat_threads (lifecycle) WHERE lifecycle <> 'open';

-- ─── case_volunteer_chat_threads (061) — staff ↔ volunteer ↔ beneficiary ─
-- Also had no state column.
ALTER TABLE case_volunteer_chat_threads
  ADD COLUMN IF NOT EXISTS lifecycle VARCHAR(16) NOT NULL DEFAULT 'open',
  ADD COLUMN IF NOT EXISTS lifecycle_reason TEXT,
  ADD COLUMN IF NOT EXISTS lifecycle_changed_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS lifecycle_changed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS archived_by INTEGER REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE case_volunteer_chat_threads DROP CONSTRAINT IF EXISTS chk_case_vol_chat_threads_lifecycle;
ALTER TABLE case_volunteer_chat_threads
  ADD CONSTRAINT chk_case_vol_chat_threads_lifecycle
  CHECK (lifecycle IN ('open','paused','ended'));

CREATE INDEX IF NOT EXISTS idx_case_vol_chat_threads_archived
  ON case_volunteer_chat_threads (archived_at) WHERE archived_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_case_vol_chat_threads_lifecycle
  ON case_volunteer_chat_threads (lifecycle) WHERE lifecycle <> 'open';

-- ─── DOWN (verified by hand against a local database) ────────────────────
-- ALTER TABLE chat_threads
--   DROP CONSTRAINT IF EXISTS chk_chat_threads_lifecycle,
--   DROP COLUMN IF EXISTS lifecycle, DROP COLUMN IF EXISTS lifecycle_reason,
--   DROP COLUMN IF EXISTS lifecycle_changed_at, DROP COLUMN IF EXISTS lifecycle_changed_by,
--   DROP COLUMN IF EXISTS archived_at, DROP COLUMN IF EXISTS archived_by;
-- ALTER TABLE marriage_chat_threads
--   DROP CONSTRAINT IF EXISTS chk_marriage_chat_threads_lifecycle,
--   DROP COLUMN IF EXISTS lifecycle, DROP COLUMN IF EXISTS lifecycle_reason,
--   DROP COLUMN IF EXISTS lifecycle_changed_at, DROP COLUMN IF EXISTS lifecycle_changed_by,
--   DROP COLUMN IF EXISTS archived_at, DROP COLUMN IF EXISTS archived_by;
-- ALTER TABLE staff_chat_threads
--   DROP CONSTRAINT IF EXISTS chk_staff_chat_threads_lifecycle,
--   DROP COLUMN IF EXISTS lifecycle, DROP COLUMN IF EXISTS lifecycle_reason,
--   DROP COLUMN IF EXISTS lifecycle_changed_at, DROP COLUMN IF EXISTS lifecycle_changed_by,
--   DROP COLUMN IF EXISTS archived_at, DROP COLUMN IF EXISTS archived_by;
-- ALTER TABLE case_volunteer_chat_threads
--   DROP CONSTRAINT IF EXISTS chk_case_vol_chat_threads_lifecycle,
--   DROP COLUMN IF EXISTS lifecycle, DROP COLUMN IF EXISTS lifecycle_reason,
--   DROP COLUMN IF EXISTS lifecycle_changed_at, DROP COLUMN IF EXISTS lifecycle_changed_by,
--   DROP COLUMN IF EXISTS archived_at, DROP COLUMN IF EXISTS archived_by;
-- DELETE FROM schema_migrations WHERE version = '118_chat_lifecycle.sql';
