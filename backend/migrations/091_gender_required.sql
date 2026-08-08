-- 091 — Gender is mandatory at sign-up.
--
-- Required/optional/hidden per field lives in registration_field_rules and is
-- editable from the Admin Panel (migration 045, tri-state since 056), so this
-- is a data change rather than a code one — the app already enforces whatever
-- state this table holds, and an admin can still flip it back.
--
--   gender       — the app's own sign-up form
--   user_gender  — the "New user" form in the Admin Panel (migration 057),
--                  set to match so a staff-created account can't skip a field
--                  the app makes mandatory.
--
-- marriage_gender is deliberately NOT touched: that's the separate
-- marriage/engagement profile form, and its own rules stay as the admin set
-- them.
UPDATE registration_field_rules
   SET state = 'required'
 WHERE field_key IN ('gender', 'user_gender')
   AND state <> 'hidden';   -- never resurrect a field an admin switched off

-- Immutability (the other half of the requirement: "after that he should not
-- be able to change his gender") is enforced in the profile handler, not here
-- — a CHECK constraint can't express "only when the old value was blank", and
-- staff still need to be able to correct a wrong value from the Admin Panel.
