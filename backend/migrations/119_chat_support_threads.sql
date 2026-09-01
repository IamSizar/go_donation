-- 119_chat_support_threads.sql
--
-- Tells a SUPPORT thread apart from a donor ↔ campaign-owner one.
--
-- WHY THIS IS NEEDED
-- "Message the staff team" (the events section's support tile, and the
-- Messages screen's support entry) creates an ordinary row in chat_threads:
-- the user as donor_user_id, the nominated staff account as owner_user_id and
-- no campaign. Nothing on the row said what it was, so staff had one list —
-- the donor↔owner oversight page — with support requests mixed into it and no
-- way to filter, sort or count them. This column is what the events section's
-- support view selects on.
--
-- WHY status STARTS ACTIVE FOR THEM (enforced in code, not here)
-- A donor↔owner thread starts 'pending' because the other party has to
-- CONSENT to being contacted. Support has no such question: the user asked to
-- reach staff and staff are the recipient by policy. Left pending, the app
-- opened a conversation the user could not post to (POST /chats/:id/messages
-- answers 409 unless the thread is active) and the message sat unsent until
-- somebody accepted it in the app — which is not where staff work.
--
-- BACKFILL: none is needed or possible. No support thread has ever been
-- created on production: the endpoint answers 503 until an account is
-- nominated in the dashboard (Settings -> support user) and none ever was.
-- Every existing row is therefore genuinely 'direct', which is the default.

ALTER TABLE chat_threads
  ADD COLUMN IF NOT EXISTS kind VARCHAR(16) NOT NULL DEFAULT 'direct';

ALTER TABLE chat_threads DROP CONSTRAINT IF EXISTS chk_chat_threads_kind;
ALTER TABLE chat_threads
  ADD CONSTRAINT chk_chat_threads_kind CHECK (kind IN ('direct', 'support'));

-- The support view's only filter, and the donor page's new one. Partial: the
-- support rows are the small minority and the 'direct' side is already served
-- by the existing per-party indexes.
CREATE INDEX IF NOT EXISTS idx_chat_threads_kind_support
  ON chat_threads (updated_at DESC)
  WHERE kind = 'support';
