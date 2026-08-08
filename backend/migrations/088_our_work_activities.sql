-- 088 — "Tenth: Details of the Our Work Section".
--
-- Almost all of this spec is already satisfied by existing structures:
--
--   "Details of Each Post" — media_posts already carries every field:
--     activity name        -> title / title_ar / title_sorani / title_badini
--     activity date        -> event_date
--     activity location    -> location (+ _ar / _sorani / _badini)
--     short description    -> body (+ 4 languages)
--     activity photos      -> media_url (cover) + gallery (text[])
--     activity videos      -> video_url
--
--   "Ability to add new sections in the future" — media_categories is an
--   admin-managed taxonomy with full CRUD, so a new activity type is a row.
--
-- The one thing missing was structure: the spec splits the activity list into
-- "Humanitarian Assistance" (its own section / dropdown) and "Other
-- Programs", and the taxonomy had no way to express which list a category
-- belongs to. That's what this migration adds, plus the spec's own list.

-- 1. Group the taxonomy. Existing rows default to 'programs'; the group is
--    editable from the Admin Panel like any other category field.
ALTER TABLE media_categories
  ADD COLUMN IF NOT EXISTS group_key VARCHAR(32) NOT NULL DEFAULT 'programs';

-- The categories the app shipped with are humanitarian aid types, so put them
-- in the humanitarian group rather than leaving them mislabelled.
UPDATE media_categories
   SET group_key = 'humanitarian'
 WHERE slug IN ('relief','food','water','health','orphans','shelter','winter','ramadan');

-- 2. The spec's activity list. Slugs that already exist are left untouched
--    (ON CONFLICT), so the seeded set above keeps its translations.
INSERT INTO media_categories (slug, name_en, name_ar, name_ckb, name_kmr, group_key, display_order) VALUES
  -- Humanitarian Assistance
  ('orphan_sponsorship', 'Orphan sponsorship',        'كفالة الأيتام',        'کفالەتی هەتیوان',     'کەفالەتا سێویان',      'humanitarian', 20),
  ('widow_sponsorship',  'Widow sponsorship',         'كفالة الأرامل',        'کفالەتی بێوەژنان',    'کەفالەتا بیوەژنان',    'humanitarian', 21),
  ('food_baskets',       'Food basket distribution',  'توزيع السلال الغذائية','دابەشکردنی سەبەتەی خۆراک','بەلاڤکرنا سەبەتێن خوارنێ','humanitarian', 22),
  ('clothing_dist',      'Clothing distribution',     'توزيع الملابس',        'دابەشکردنی جلوبەرگ',  'بەلاڤکرنا جلکان',      'humanitarian', 23),
  ('medical_assistance', 'Medical assistance',        'المساعدات الطبية',     'یارمەتی پزیشکی',      'هاریکاریا پزیشکی',     'humanitarian', 24),
  ('seasonal_projects',  'Seasonal projects',         'المشاريع الموسمية',    'پڕۆژە وەرزییەکان',    'پرۆژێن وەرزی',         'humanitarian', 25),
  ('other_humanitarian', 'Other humanitarian programs','برامج إنسانية أخرى',  'بەرنامەی مرۆیی تر',   'بەرنامێن مرۆڤی یێن دی','humanitarian', 26),
  -- Other Programs
  ('childhood',          'Childhood programs',        'برامج الطفولة',        'بەرنامەکانی منداڵی',  'بەرنامێن زاڕۆکاتیێ',   'programs', 40),
  ('womens_programs',    'Women''s programs',         'برامج المرأة',         'بەرنامەکانی ژنان',    'بەرنامێن ژنان',        'programs', 41),
  ('livelihoods',        'Livelihoods',               'سبل العيش',            'بژێوی ژیان',          'بژیڤ',                 'programs', 42),
  ('environment',        'Environment and climate',   'البيئة والمناخ',       'ژینگە و کەشوهەوا',    'ژینگەه و کەشوهەوا',    'programs', 43),
  ('heritage_culture',   'Heritage and culture',      'التراث والثقافة',      'میرات و کولتوور',     'میرات و چاند',         'programs', 44),
  ('peacebuilding',      'Peacebuilding',             'بناء السلام',          'ئاشتیخوازی',          'ئاشتیڤانی',            'programs', 45),
  ('exhibitions',        'Exhibitions and festivals', 'المعارض والمهرجانات',  'پێشانگا و فیستیڤاڵ',  'پێشانگەه و فیستیڤال',  'programs', 46),
  ('education_training', 'Education and training',    'التعليم والتدريب',     'خوێندن و ڕاهێنان',    'خواندن و راهێنان',     'programs', 47),
  ('community_activities','Community activities',     'الأنشطة المجتمعية',    'چالاکی کۆمەڵایەتییەکان','چالاکیێن جڤاکی',     'programs', 48)
ON CONFLICT (slug) DO NOTHING;
