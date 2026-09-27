-- 137 — Events (marriage) profile: ID card, residence card and ration card are
-- each asked as their OWN document, front AND back.
--
-- Until now the form asked for one "Golden Square document" — a single photo
-- of all three cards laid side by side. Staff could not read a card that had
-- been shrunk to a third of a photo, and nothing forced the back to be shown.
-- Six new photo columns (uploaded via POST /api/uploads, stored as returned
-- paths). golden_square_url stays: profiles already submitted keep their photo
-- and the dashboard still shows it, but the form no longer asks for it.
ALTER TABLE marriage_profiles
  ADD COLUMN IF NOT EXISTS id_photo_url              TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS id_photo_back_url         TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS residence_card_url        TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS residence_card_back_url   TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS ration_card_url           TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS ration_card_back_url      TEXT NOT NULL DEFAULT '';

-- One rule per document; "filled" means front AND back. Required by default —
-- the client's ask — and still switchable from the dashboard's field rules.
INSERT INTO registration_field_rules (field_key, state, display_order) VALUES
  ('marriage_id_photo',             'required', 443),
  ('marriage_residence_card_photo', 'required', 444),
  ('marriage_ration_card_photo',    'required', 445)
ON CONFLICT (field_key) DO NOTHING;

-- The merged document is replaced by the three above.
UPDATE registration_field_rules SET state = 'hidden'
 WHERE field_key = 'marriage_golden_square';
