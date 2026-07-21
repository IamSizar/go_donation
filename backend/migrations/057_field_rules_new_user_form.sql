-- 057 — Note #34: the admin dashboard's "Add New User" window only ever
-- collected phone/full_name/role, unlike the Edit User form (and the
-- backend's PATCH /api/admin/users/:id) which already handle the full
-- user_profiles set. Seeds Field Rules entries for those fields with a
-- "user_" prefix — same mechanism as "case_" (Beneficiary, migration 054)
-- and "marriage_" (Marriage, migration 056) — so a Super-Admin can mark
-- each Required/Optional/Hidden independently of the public sign-up form's
-- own (un-prefixed) rules. phone and role aren't included: phone is the
-- required login identifier and role is an admin classification choice,
-- neither is applicant data collected about the person.

INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  ('user_full_name',       'optional', 301),
  ('user_gender',          'optional', 302),
  ('user_date_of_birth',   'optional', 303),
  ('user_address',         'optional', 304),
  ('user_city',            'optional', 305),
  ('user_occupation',      'optional', 306),
  ('user_housing_status',  'optional', 307),
  ('user_family_size',     'optional', 308),
  ('user_monthly_income',  'optional', 309),
  ('user_availability',    'optional', 310),
  ('user_experience',      'optional', 311),
  ('user_skills',          'optional', 312),
  ('user_profile_picture', 'optional', 313)
ON CONFLICT (field_key) DO NOTHING;
