-- 116 — K19: the supervised donor↔beneficiary chat refuses messages carrying a
-- phone number or an email address, and records that it did.
--
-- THE GAP THIS CLOSES
-- The supervised thread itself has existed since migration 012, and staff can
-- already read it, relay in it and claim it (Note #36). What was never built is
-- the half the client named the reason for:
--
--   "منع تبادل البيانات الشخصية منعاً للابتزاز"
--
-- Nothing stopped the two parties agreeing, inside the supervised thread, to
-- carry on somewhere it could not be supervised. The block lives in Go
-- (internal/moderation/contactfilter.go) because it must run BEFORE the insert
-- — every new message fans out an 80-character push preview, so a number that
-- reached the database would already have left the server.
--
-- WHY A TABLE AT ALL, IF THE MESSAGE IS NEVER STORED
-- Because K19 casts the employee as "mediator AND MONITOR", and a refusal that
-- is invisible gives the monitor nothing. One blocked message is a
-- misunderstanding; the same sender blocked eleven times in an afternoon is the
-- extortion pattern the row exists to catch, and it is only visible if the
-- attempts are counted. The refusal is shown to the sender and recorded for
-- staff; those are two different audiences and only one of them is served by
-- the error message.
--
-- WHY THE NUMBER ITSELF IS NOT IN THIS TABLE
-- This is the important column decision. redacted_body stores the message with
-- every match replaced by "•••" — the wording survives, the contact detail does
-- not. Storing the raw body would have quietly turned the supervision log into
-- a searchable directory of exactly the phone numbers this row exists to keep
-- out of the thread, reachable by anyone with `messages:view`. The surrounding
-- words are what tell a supervisor whether they are reading coercion or a
-- confused first-time user; the digits add nothing to that judgement and carry
-- all of the risk. kind and match_count carry the rest of the signal.
--
-- WHY NOT A UNIQUE KEY / ONE ROW PER SENDER
-- The opposite of migration 115's choice, deliberately. There, one live block
-- per actor was the whole point. Here the REPETITION is the signal, so every
-- attempt is appended and nothing is collapsed.
--
-- TIMESTAMP: CURRENT_TIMESTAMP into a naive column, i.e. the database's own
-- local clock, matching chat_messages.created_at (migration 012) which these
-- rows are read alongside. The Go side never supplies a time. Deployment
-- timezone is Asia/Baghdad, so a Go-supplied UTC time would sort three hours
-- away from the messages it sits between.
--
-- ADDITIVE ONLY: one new table. No column is added, dropped, retyped or
-- backfilled anywhere else, and no existing row is read differently. With this
-- applied and the Go code reverted, nothing writes or reads the table and the
-- chat behaves exactly as it does today.

CREATE TABLE IF NOT EXISTS chat_contact_blocks (
  id             BIGSERIAL PRIMARY KEY,
  -- The supervised thread the attempt was made in. CASCADE: a deleted thread
  -- has no supervision history worth keeping.
  thread_id      BIGINT    NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
  -- Who tried. Never a staff member — the filter does not run on staff (see
  -- internal/handlers/chat_contact_block.go), because a relaying employee
  -- passing a number on is the supervised channel working, not failing.
  sender_user_id BIGINT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- What was found: 'phone' | 'email' | 'both'. CHECKed in the database rather
  -- than only in Go, so a future writer cannot invent a fourth value that the
  -- dashboard would not know how to label.
  kind           VARCHAR(8) NOT NULL CHECK (kind IN ('phone', 'email', 'both')),
  -- How many separate matches were in the one message. Three numbers in a
  -- single message reads very differently from one.
  match_count    INTEGER   NOT NULL DEFAULT 1 CHECK (match_count > 0),
  -- The message with the contact details replaced by "•••". See above.
  redacted_body  TEXT      NOT NULL,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- The two reads that exist. Both are covered deliberately rather than
-- speculatively: staff open one thread's history ("what has been tried here?"),
-- and the count of recent attempts by one sender is what turns a slip into a
-- pattern. No other query touches this table, so no other index is created.
CREATE INDEX IF NOT EXISTS idx_chat_contact_blocks_thread
  ON chat_contact_blocks (thread_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_contact_blocks_sender
  ON chat_contact_blocks (sender_user_id, created_at DESC);

-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- This repo's runner (internal/db/migrate.go) is forward-only and records each
-- file in schema_migrations; there is no .down.sql convention, so the reversal
-- is recorded here and WAS EXECUTED against a local database (UP → DOWN → UP)
-- before this migration was committed:
--
--   DROP TABLE IF EXISTS chat_contact_blocks;
--   DELETE FROM schema_migrations WHERE version = '116_chat_contact_blocks.sql';
--
-- Dropping the table drops its two indexes with it; they are not named
-- separately in the reversal because an index cannot outlive its table.
--
-- Reversing loses only the record that messages were refused. It loses no
-- message (none was ever stored — the refusal happens before the insert), no
-- thread, and no account state. chat_threads, chat_messages and chat_reads are
-- untouched by this migration in both directions.

