-- 031_sponsorship_reminders.sql — task #20 (Reminder scheduler).
--
-- Adds a per-cycle marker so the reminder scheduler sends AT MOST ONE
-- payment-due reminder per sponsorship due date. It stores the next_due_date
-- the last reminder was sent for; the scheduler only reminds when
-- last_reminder_due_date IS DISTINCT FROM next_due_date, so:
--   * once a reminder goes out, it won't re-fire on the next tick, and
--   * when a payment advances next_due_date to a new cycle, the marker no
--     longer matches and the sponsorship re-arms automatically.
--
-- Idempotent: safe to run repeatedly (ADD COLUMN IF NOT EXISTS).

ALTER TABLE sponsorships
  ADD COLUMN IF NOT EXISTS last_reminder_due_date DATE;

-- Partial index over the exact rows the scheduler scans each tick: active
-- sponsorships that still have a due date. Keeps the periodic query cheap
-- even as the table grows.
CREATE INDEX IF NOT EXISTS idx_sponsorships_reminder_scan
  ON sponsorships (next_due_date)
  WHERE status = 'active' AND next_due_date IS NOT NULL;
