-- 138 — Volunteer registration: ID card, residence card and ration card are
-- each asked as their OWN document, front AND back (follow-up to 137, which did
-- the same for the events profile).
--
-- The volunteer form asked for a merged "Golden Square" photo of all three
-- cards, and the ration card had only a front. The ID card (127) and residence
-- card (127) already have back columns; the ration card gets its own now.
-- golden_square_photo_path stays: accounts that already sent one keep it and the
-- dashboard still shows it.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS ration_card_photo_back_path TEXT NOT NULL DEFAULT '';

-- Required by default (the client's ask); still switchable in the dashboard's
-- field rules. The merged document is replaced by the three above.
UPDATE registration_field_rules SET state = 'required'
 WHERE field_key IN ('volunteer_id_photo', 'volunteer_ration_card_photo',
                     'volunteer_residence_card_photo');
UPDATE registration_field_rules SET state = 'hidden'
 WHERE field_key = 'volunteer_golden_square_photo';
