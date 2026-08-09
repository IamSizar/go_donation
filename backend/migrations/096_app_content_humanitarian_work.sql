-- 096 — Seed the "Our Humanitarian Work" page into the app_content CMS.
--
-- The slug was added to the handler's allowedSlugs and given both a dashboard
-- editor and an app drawer entry, but no row was ever inserted the way
-- migration 025 (terms) and 041 (about/contact) did for the others. So
-- GET /api/content/humanitarian-work 404s, which surfaced as:
--
--   * dashboard — a red "Content not found." banner over an empty editor,
--     even though saving would have created the row perfectly well (the admin
--     PUT upserts);
--   * app — "content load failed" with a Retry button that could never
--     succeed, for every user who opened the page.
--
-- Draft text the admin should review and edit, same as 041. Idempotent, so it
-- will not overwrite anything an admin has already written by hand.
INSERT INTO app_content (slug, title_en, title_ar, title_ckb, title_kmr, body_en, body_ar, body_ckb, body_kmr)
VALUES
  ('humanitarian-work',
   'Our Humanitarian Work', 'عملنا الإنساني', 'کاری مرۆییمان', 'کارێ مە یێ مرۆڤی',
   'We deliver aid to families in need through our grantors, partners and volunteers. Every campaign is reviewed before it goes live, and every donation is tracked from the giver to the family that receives it.',
   'نقدم المساعدة للعائلات المحتاجة من خلال المانحين والشركاء والمتطوعين. تتم مراجعة كل حملة قبل نشرها، ويُتابَع كل تبرع من المتبرع حتى العائلة المستفيدة.',
   'یارمەتی بە خێزانە پێویستدارەکان دەگەیەنین لە ڕێگەی بەخشەران و هاوبەشان و خۆبەخشانمانەوە. هەموو کەمپینێک پێش بڵاوکردنەوە پێداچوونەوەی بۆ دەکرێت، و هەموو بەخشینێک لە بەخشەرەوە تا ئەو خێزانەی وەریدەگرێت بەدواداچوونی بۆ دەکرێت.',
   'ئەم هاریکاریێ دگەهینین مالبەتێن پێدڤی ب رێکا بەخشەران و هەڤپشکان و خۆبەخشێن مە. هەر کەمپینەک بەری بەلاڤکرنێ تێت پشکنین، و هەر بەخشینەک ژ بەخشەری هەتا وێ مالبەتا وەردگریت تێت شوپاندن.')
ON CONFLICT (slug) DO NOTHING;
