-- 132 — App rename follow-up: migration 131 only fixed `app_content.body_*`.
-- `app_content_sections` (K12, migration 111) is a SEPARATE table that was
-- backfilled from `app_content` and never touched by 131, so `GET
-- /api/content/:slug` was still returning "BalanceNex" inside its `sections`
-- array even after 131 shipped. Same REPLACE() approach, same slugs, same
-- ZWNJ transliteration handling for slug='about' — see 131 for the full
-- rationale.
UPDATE app_content_sections
   SET body_en  = REPLACE(body_en,  'BalanceNex', 'Tawazzn'),
       body_ar  = REPLACE(body_ar,  'BalanceNex', 'توازن'),
       body_ckb = REPLACE(body_ckb, 'BalanceNex', 'توازن'),
       body_kmr = REPLACE(body_kmr, 'BalanceNex', 'توازن')
 WHERE slug = 'terms';

UPDATE app_content_sections
   SET body_en  = REPLACE(body_en,  'BalanceNex', 'Tawazzn'),
       body_ar  = REPLACE(body_ar,  'بالانس' || chr(8204) || 'نكس', 'توازن'),
       body_ckb = REPLACE(body_ckb, 'بالانس' || chr(8204) || 'نێکس', 'توازن'),
       body_kmr = REPLACE(body_kmr, 'بالانس' || chr(8204) || 'نێکس', 'توازن')
 WHERE slug = 'about';
