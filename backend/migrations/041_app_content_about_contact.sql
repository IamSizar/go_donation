-- 041 — Seed About Us + Contact pages into the app_content CMS (#35). Reuses
-- the #9 app_content table (public GET /api/content/:slug, admin PUT). Draft
-- text the admin should review/edit. Idempotent (ON CONFLICT DO NOTHING).
INSERT INTO app_content (slug, title_en, title_ar, title_ckb, title_kmr, body_en, body_ar, body_ckb, body_kmr)
VALUES
  ('about',
   'About Us', 'من نحن', 'دەربارەی ئێمە', 'دەربارەی مە',
   'BalanceNex is a humanitarian donations and community platform connecting grantors with those who are eligible for support.',
   'بالانس‌نكس منصة إنسانية للتبرعات والمجتمع تربط المانحين بالمستحقين للدعم.',
   'بالانس‌نێکس پلاتفۆرمێکی مرۆییە بۆ بەخشین و کۆمەڵگا کە بەخشەران بە مستحقان دەبەستێتەوە.',
   'بالانس‌نێکس پلاتفۆرمەکا مرۆڤی یە بۆ بەخشین و جڤاکێ کو بەخشەران ب مستەحەقان ڤەدگرت.'),
  ('contact',
   'Contact Us', 'اتصل بنا', 'پەیوەندیمان پێوە بکە', 'پەیوەندی ب مە بکە',
   'Reach us by email or phone. Our team is here to help.',
   'تواصل معنا عبر البريد الإلكتروني أو الهاتف. فريقنا هنا لمساعدتك.',
   'لە ڕێگەی ئیمەیڵ یان تەلەفۆن پەیوەندیمان پێوە بکە. تیمەکەمان لێرەیە بۆ یارمەتیت.',
   'ب رێکا ئیمەیل یان تەلەفۆنێ پەیوەندی ب مە بکە. تیما مە ل ڤێرەیە بۆ هاریکاریا تە.')
ON CONFLICT (slug) DO NOTHING;
