-- 127 — Client report, 2026-09-22: "لا يوجد خيار لإضافة الوجه الثاني للهوية
-- وبطاقة السكن في جميع حسابات التسجيل" (no option to attach the second side
-- of the national ID or the residence card, in any registration account).
--
-- id_photo_path and residence_card_photo_path (072/078) only ever held one
-- image each — the front. Adding the back as its own column rather than a
-- second file packed into the same path: every other attachment on this
-- form is one column per document, and a document-viewer that expects one
-- URL per field would otherwise have to guess which of two files in a
-- delimited string is which.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS id_photo_back_path TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS residence_card_photo_back_path TEXT NOT NULL DEFAULT '';
