-- 131 — App rename: "BalanceNex" → "Tawazzn" / "توازن" (client report — full
-- rename, no old name left anywhere). Everything else about the rename is
-- native config/UI strings shipped in the app/admin-web builds themselves;
-- this migration is the one piece that's DATA, not code — the Terms &
-- Conditions and About Us text seeded by migrations 025 and 041 already
-- shipped to production with the old name baked into the row content, so a
-- code-only rename would leave those two pages showing "BalanceNex" forever
-- (migrations 025/041 already ran; editing those files does nothing to the
-- live rows — see cd1bf46-style precedent of "the file isn't the data").
--
-- REPLACE() handles slug='terms' (all 4 langs literally spell "BalanceNex").
-- slug='about' is different: its ar/ckb/kmr bodies never had the Latin name
-- at all — they used a phonetic Arabic-script transliteration
-- ("بالانس‌نكس" / "بالانس‌نێکس", with a ZWNJ between the two halves), so
-- those need their own REPLACE targeting that exact transliteration, not
-- "BalanceNex". The en body there is a normal literal match.
UPDATE app_content
   SET body_en  = REPLACE(body_en,  'BalanceNex', 'Tawazzn'),
       body_ar  = REPLACE(body_ar,  'BalanceNex', 'توازن'),
       body_ckb = REPLACE(body_ckb, 'BalanceNex', 'توازن'),
       body_kmr = REPLACE(body_kmr, 'BalanceNex', 'توازن')
 WHERE slug = 'terms';

UPDATE app_content
   SET body_en  = REPLACE(body_en,  'BalanceNex', 'Tawazzn'),
       body_ar  = REPLACE(body_ar,  'بالانس' || chr(8204) || 'نكس', 'توازن'),
       body_ckb = REPLACE(body_ckb, 'بالانس' || chr(8204) || 'نێکس', 'توازن'),
       body_kmr = REPLACE(body_kmr, 'بالانس' || chr(8204) || 'نێکس', 'توازن')
 WHERE slug = 'about';
