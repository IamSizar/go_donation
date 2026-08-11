-- 098 — "4. Technical Support": let staff answer a ticket, and let the user
-- see the answer.
--
-- support_tickets could only ever be written to. A user could send a message
-- (POST /api/support) and staff could change its status from the Admin Panel,
-- but there was no reply column and no endpoint returning a user their own
-- tickets — so "track the request status and responses" was impossible from
-- the app: nothing to read, and no answer to read even if there had been.
ALTER TABLE support_tickets
  ADD COLUMN IF NOT EXISTS admin_reply TEXT,
  ADD COLUMN IF NOT EXISTS replied_at  TIMESTAMP,
  ADD COLUMN IF NOT EXISTS replied_by  INTEGER;

-- The app asks for "my tickets, newest first" on every open of the support
-- screen, and the escalation check counts a user's unresolved tickets.
CREATE INDEX IF NOT EXISTS idx_support_tickets_user
  ON support_tickets (user_id, created_at DESC);
