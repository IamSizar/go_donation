-- 081 — "Fourth: My Engagement / Marriage Section" spec:
-- "Housing Information" and "Housing Type".
--
-- These live on marriage_profiles for the same reason as migration 079's
-- identification columns: a marriage profile is a separate entity with its
-- own visibility_level and review status, and the applicant may present a
-- different address here than on their main account. marriage_profiles.city
-- already exists (migration 001) and is kept as-is.
--
-- Note: years_current_residence / previous_residence /
-- years_previous_residence have no equivalent anywhere else in the app —
-- they are unique to this spec.
ALTER TABLE marriage_profiles
  ADD COLUMN IF NOT EXISTS governorate TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS housing_side TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS neighborhood TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS nearest_landmark TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS gps_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS gps_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS years_current_residence TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS previous_residence TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS years_previous_residence TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS housing_type TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS rental_amount TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS housing_area TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS floors_count TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS rooms_count TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS families_count TEXT NOT NULL DEFAULT '';

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  ('marriage_governorate',              'required', 390),
  ('marriage_housing_side',             'optional', 391),
  ('marriage_neighborhood',             'optional', 392),
  ('marriage_nearest_landmark',         'optional', 393),
  ('marriage_gps_location',             'optional', 394),
  ('marriage_years_current_residence',  'optional', 395),
  ('marriage_previous_residence',       'optional', 396),
  ('marriage_years_previous_residence', 'optional', 397),
  ('marriage_housing_type',             'optional', 398),
  ('marriage_rental_amount',            'optional', 399),
  ('marriage_housing_area',             'optional', 400),
  ('marriage_floors_count',             'optional', 401),
  ('marriage_rooms_count',              'optional', 402),
  ('marriage_families_count',           'optional', 403)
ON CONFLICT (field_key) DO NOTHING;
