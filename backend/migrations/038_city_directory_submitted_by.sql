-- 038 — Track who submitted a City Guide place (#30 "Add an Activity").
-- User-submitted places enter with status='pending' and this column records the
-- submitting user so the admin queue can show provenance. No FK (handlers
-- validate); idempotent.
ALTER TABLE city_directory_entries
  ADD COLUMN IF NOT EXISTS submitted_by INTEGER;
