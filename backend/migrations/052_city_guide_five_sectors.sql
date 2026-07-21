-- 052_city_guide_five_sectors.sql
--
-- Note #19 — replaces the 6 free-form City Guide sectors with 5 fixed main
-- sectors, and adds a new mandatory "Sector Type" (government/private)
-- classification per entry.
--
-- IMPORTANT: `sectors` on city_directory_entries stays a TEXT[] column (not
-- converted to a scalar) — the Flutter app reads it as an array in 4 places
-- (community_controller.dart's sector filter, community_detail_screen.dart,
-- community_services_section.dart, and the add_activity_screen.dart submit
-- payload). A scalar column would silently break sector filtering/display
-- app-side (all `is List` guards would just return empty, no crash but no
-- data). The admin dashboard now enforces "one sector per entry" at the UI
-- layer (single-select that writes a 1-element array) instead — same
-- backward-compatible on-the-wire shape, zero Flutter changes needed.

-- Remap existing entries' sector tags onto the new 5-slug taxonomy where
-- there's a clean conceptual match; drop the ones that don't map cleanly
-- (worship, relief) so no entry is left pointing at a slug that's about to
-- stop existing in city_sectors. Admins can re-tag these from City Guide.
UPDATE city_directory_entries SET sectors = array_replace(sectors, 'healthcare', 'health');
UPDATE city_directory_entries SET sectors = array_replace(sectors, 'markets', 'commercial');
UPDATE city_directory_entries SET sectors = array_remove(sectors, 'worship');
UPDATE city_directory_entries SET sectors = array_remove(sectors, 'relief');
-- 'government' and 'education' slugs are reused as-is (same word, new
-- broader definition) — no remap needed for those two.

-- Reseed city_sectors: out with the old 6, in with the client's 5 fixed
-- main categories. No FK constraint ties city_sectors rows to entries'
-- `sectors` array (it's slug-string matching), so this is safe post-remap.
DELETE FROM city_sectors;
INSERT INTO city_sectors (slug, name_en, name_ar, name_ckb, name_kmr, display_order) VALUES
  ('government',  'Governmental & Sovereign Departments', 'الدوائر الحكومية والسيادية',   'دەزگا حکومی و سەروەری',      'دەزگەهێن حکومی و سەروەری',    1),
  ('education',   'Educational & Academic Sector',        'القطاع التعليمي والأكاديمي',  'بواری پەروەردە و ئەکادیمی',  'خەبات وارێ پەروەردێ و ئەکادیمی', 2),
  ('health',      'Health & Medical Sector',               'القطاع الصحي والطبي',         'بواری تەندروستی و پزیشکی',   'خەبات وارێ تەندرستیێ و پزیشکی',  3),
  ('commercial',  'Commercial & Service Sector',           'القطاع التجاري والخدمي',      'بواری بازرگانی و خزمەتگوزاری','خەبات وارێ بازرگانی و خزمەتێ',   4),
  ('industrial',  'Industrial & Productive Sector',        'القطاع الصناعي والإنتاجي',    'بواری پیشەسازی و بەرهەمهێنان','خەبات وارێ پیشەسازی و بەرهەمانینێ', 5)
ON CONFLICT (slug) DO NOTHING;

-- New mandatory field: is this place government-run or private/non-profit?
-- Defaults existing rows (and the mobile app's self-submission path, which
-- doesn't send this field) to 'private' — the safer generic bucket, since
-- most directory entries are shops/clinics/services rather than government
-- offices. Admins can review and correct the handful of real government ones.
ALTER TABLE city_directory_entries ADD COLUMN IF NOT EXISTS sector_type VARCHAR(16) NOT NULL DEFAULT 'private'
  CHECK (sector_type IN ('government', 'private'));
