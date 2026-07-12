-- 050_donation_delivery_statuses.sql
--
-- Widen donations.delivery_status to cover the full delivery lifecycle the admin
-- dashboard offers. The original CHECK (migration 001) only allowed
--   registered / received / under_review / delivered / cancelled
-- so the dashboard's Archive ('archived') and Suspend ('suspended' / 'paused')
-- options were silently rejected at the database layer — the UPDATE failed the
-- CHECK and the status change never persisted.
--
-- Widening a CHECK is safe: every existing row already satisfied the narrower
-- old constraint, so it trivially satisfies this superset. The constraint name
-- 'donations_delivery_status_check' is Postgres's auto-generated name for the
-- unnamed column-level CHECK created in migration 001.

ALTER TABLE donations DROP CONSTRAINT IF EXISTS donations_delivery_status_check;
ALTER TABLE donations ADD CONSTRAINT donations_delivery_status_check
  CHECK (delivery_status IN (
    'registered', 'received', 'under_review', 'delivered',
    'paused', 'suspended', 'archived', 'cancelled'
  ));
