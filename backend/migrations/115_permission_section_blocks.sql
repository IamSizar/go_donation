-- 115 — H14: a burst of permission changes freezes the الصلاحيات section and
-- ends the acting session, and an SMS code lifts the freeze.
--
-- THE GAP THIS CLOSES
-- The only thing standing between a runaway session and the whole permission
-- matrix was a one-minute 429 counter that lives IN MEMORY and is DISABLED
-- unless PERM_CHANGE_MAX_PER_MIN happens to be set (see
-- internal/handlers/admin_permissions_ratelimit.go). Nothing blocked, nothing
-- logged the account out, and nothing had to be answered out of band to carry
-- on. The client asked for all three:
--
--   "حظر مؤقت وتسجيل خروج تلقائي فوري مع رسالة تأكيد SMS لرفع الحظر، عند
--    اكتشاف عمليات تعديل/حذف متكررة وسريعة في هذا القسم"
--
-- WHY THE COUNTER IS NOT IN THIS TABLE
-- Because it already exists. permission_audit_log (migration 015) records every
-- single permission change with actor_id and created_at, is immutable, and is
-- shared by every replica. "How many changes has this actor made in the last N
-- seconds" is one COUNT against it. A second counter would have had to be kept
-- in step with the first, and the two would have drifted the first time someone
-- added a write path — which is exactly how the in-memory limiter ended up
-- knowing about only some of them.
--
-- So this table holds only what the audit log cannot: the BLOCK itself.
--
-- WHY expires_at IS A COLUMN AND NOT A CONSTANT
-- The block must never outlive the only channel that can lift it. With a real
-- gateway configured — SMS, or email when that is the only one set up — the code
-- is the way out and the block can safely run longer; with no gateway at all,
-- which is every environment today, there IS no code, and a block that could
-- only be lifted by a message nobody can send would be a permanent lockout from
-- the one screen that fixes everything else. The Go side therefore writes a
-- longer expiry when a code was actually delivered and a short one when nothing
-- could be, and says which in the refusal. One column, two values, one rule.
--
-- EVERY TIMESTAMP HERE IS THE DATABASE'S OWN LOCAL CLOCK (LOCALTIMESTAMP), which
-- is what CURRENT_TIMESTAMP writes into a naive column and therefore what
-- permission_audit_log.created_at already holds. The Go side never supplies a
-- time for these columns. That is deliberate: the deployment timezone is
-- Asia/Baghdad, so timestamps written from Go in UTC would land three hours away
-- from the audit rows they are compared against, and "how many changes has this
-- actor made since they were blocked" would read the wrong side of the gap.
--
-- ONE ROW PER ACTOR, keyed by actor_user_id: a re-trip replaces the block
-- rather than stacking blocks nobody could reason about. The history of the
-- trip is not lost — it is appended to permission_audit_log like every other
-- event on this screen.
--
-- ADDITIVE ONLY: one new table. Nothing is dropped, retyped, backfilled or
-- read differently. With this applied and the Go code reverted, nothing touches
-- the table and the section behaves exactly as it does today.

CREATE TABLE IF NOT EXISTS permission_section_blocks (
  -- Who is frozen out of the section. PK: one live block per actor.
  actor_user_id    INTEGER   NOT NULL PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  blocked_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- When the freeze lapses on its own. See the note above — this is short when
  -- no unlock code could be delivered and long when one was.
  expires_at       TIMESTAMP NOT NULL,
  -- What tripped it, kept so an operator reading the row can tell whether the
  -- threshold was sane without going to the source.
  trigger_count    INTEGER   NOT NULL,
  window_seconds   INTEGER   NOT NULL,
  -- bcrypt of the unlock code. NULL means no code exists — the block can then
  -- only lapse, and the refusal says so rather than inviting the operator to
  -- type a code that was never sent. These three are set and cleared together:
  -- a NULL in any of them means a NULL in all three.
  unlock_code_hash TEXT,
  unlock_sent_at   TIMESTAMP,
  unlock_channel   VARCHAR(16), -- 'sms' | 'email'; NULL when nothing was delivered
  unlock_attempts  INTEGER   NOT NULL DEFAULT 0,
  -- Set when the code is accepted. The row is kept rather than deleted so a
  -- lifted block stays visible as history.
  lifted_at        TIMESTAMP,
  -- How many live sessions the trip ended, for the same reason.
  sessions_ended   INTEGER   NOT NULL DEFAULT 0
);

-- The only read path is by primary key ("is THIS actor blocked?"), which the PK
-- already serves. No further index is added: there is no query that scans this
-- table, and an unused index is a write cost with no reader.

-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- This repo's runner (internal/db/migrate.go) is forward-only and records each
-- file in schema_migrations; there is no .down.sql convention, so the reversal
-- is recorded here and WAS EXECUTED against a local database (UP → DOWN → UP)
-- before this migration was committed:
--
--   DROP TABLE IF EXISTS permission_section_blocks;
--   DELETE FROM schema_migrations WHERE version = '115_permission_section_blocks.sql';
--
-- Measured on godonation_h10, with the counts at each step:
--   UP (already applied): table present, 11 columns, 0 rows, schema_migrations 114
--   DOWN:                 table absent,  0 columns,          schema_migrations 113
--   UP (re-applied):      table present, 11 columns, 0 rows, schema_migrations 114
-- role_permissions (0), permission_audit_log (89) and users (9) were identical
-- at every step — the reversal touches nothing but this table.
--
-- Reversing loses only live and lapsed blocks. No permission, no session and no
-- account state lives here — the permissions themselves are in role_permissions
-- and the trail of what happened is in permission_audit_log, both untouched.
