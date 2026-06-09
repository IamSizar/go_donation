-- Re-align IDENTITY sequences to MAX(id)+1 after loading data.
-- For empty tables this is a no-op (sequence stays at 1).
-- Pattern: setval(seq, MAX(id)+1, false)  -> next nextval() returns MAX(id)+1.

DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[
    'app_notifications',
    'app_notification_devices',
    'api_access_tokens',
    'beneficiary_cases',
    'beneficiary_case_documents',
    'beneficiary_project_requests',
    'beneficiary_project_request_comments',
    'beneficiary_project_request_likes',
    'campaigns',
    'campaigns_category',
    'campaings_datas',
    'city_directory_entries',
    'donations',
    'financial_expenses',
    'in_kind_donations',
    'marketplace_orders',
    'marketplace_products',
    'marriage_profiles',
    'media_posts',
    'partners',
    'sponsorships',
    'support_tickets',
    'users',
    'user_device_tokens',
    'user_profile_audit_logs',
    'user_profiles',
    'volunteer_applications',
    'volunteer_missions',
    'volunteer_mission_signups'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format(
      'SELECT setval(pg_get_serial_sequence(%L, %L), COALESCE((SELECT MAX(id)+1 FROM %I), 1), false)',
      t, 'id', t
    );
  END LOOP;
END $$;
