-- 074 — Eligible Recipient Registration spec: "Housing Information" section.
-- governorate/gps_lat/gps_lng already exist (migration 072, shared with the
-- grantor fields) and are reused as-is. New columns here cover the
-- Nineveh-specific side/neighborhood picker, the general neighborhood/
-- landmark fields for other governorates, and the housing-type detail block.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS housing_side TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS neighborhood TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS nearest_landmark TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS housing_type TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS rental_amount TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS housing_area TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS floors_count TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS rooms_count TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS families_count TEXT NOT NULL DEFAULT '';

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  ('recipient_housing_side',        'optional', 240),
  ('recipient_neighborhood',        'required', 241),
  ('recipient_nearest_landmark',    'optional', 242),
  ('recipient_gps_location',        'optional', 243),
  ('recipient_housing_type',        'required', 244),
  ('recipient_rental_amount',       'optional', 245),
  ('recipient_housing_area',        'optional', 246),
  ('recipient_floors_count',        'optional', 247),
  ('recipient_rooms_count',         'optional', 248),
  ('recipient_families_count',      'optional', 249)
ON CONFLICT (field_key) DO NOTHING;
