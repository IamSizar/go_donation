-- 099 — Three gaps from the Settings / About / Contact / Marketplace spec.
--
-- 1. Section-specific About Us and Contact Us.
--    "The About Us and Contact Us lists are repeated in the My Engagement
--    interface and the Comprehensive Mosul Guide, but they must contain
--    details, phone numbers and social media links DIFFERENT from those used
--    for humanitarian assistance."
--
--    Only one 'about' and one 'contact' page existed, shared by everything, so
--    the marriage service and the city guide could not carry their own contact
--    details at all. Four more app_content pages, edited from the same CMS as
--    the existing ones.
--
--    Seeded rather than left to the allowedSlugs list alone: an allowed but
--    unseeded slug 404s, which is exactly what made "Our Humanitarian Work"
--    dead-end in the app until migration 096 backfilled it.
INSERT INTO app_content (slug, title_en, title_ar, title_ckb, title_kmr,
                         body_en, body_ar, body_ckb, body_kmr)
VALUES
  ('marriage-about',
   'About My Engagement', 'عن خدمة الارتباط', 'دەربارەی خزمەتگوزاری هاوسەرگیری', 'دەربارەی خزمەتا هەڤژینیێ',
   'The engagement and marriage service helps families find a suitable match through a supervised, private process.',
   'خدمة الارتباط والزواج تساعد العائلات على إيجاد الشريك المناسب عبر عملية خاصة ومُشرَف عليها.',
   'خزمەتگوزاری هاوسەرگیری یارمەتی خێزانەکان دەدات هاوبەشی گونجاو بدۆزنەوە بە پرۆسەیەکی تایبەت و چاودێریکراو.',
   'خزمەتا هەڤژینیێ هاریکاریا مالبەتان دکەت دا هەڤپشکێ گونجای بدۆزن ب رێکا پرۆسەیەکا تایبەت و چاڤدێریکری.'),
  ('marriage-contact',
   'Contact — My Engagement', 'تواصل — خدمة الارتباط', 'پەیوەندی — هاوسەرگیری', 'پەیوەندی — هەڤژینی',
   'Reach the engagement service team directly. Replace this text with the phone, WhatsApp, email, address and social links for THIS service.',
   'تواصل مع فريق خدمة الارتباط مباشرة. استبدل هذا النص بأرقام الهاتف وواتساب والبريد والعنوان وحسابات التواصل الخاصة بهذه الخدمة.',
   'ڕاستەوخۆ پەیوەندی بە تیمی خزمەتگوزاری هاوسەرگیرییەوە بکە. ئەم دەقە بگۆڕە بە ژمارە و واتساپ و ئیمەیل و ناونیشان و هەژمارەکانی ئەم خزمەتگوزارییە.',
   'راستەوخۆ پەیوەندی ب تیما خزمەتا هەڤژینیێ بکە. ڤێ دەقێ بگوهۆرە ب ژمارە و واتساپ و ئیمەیل و ناڤونیشان و هەژمارێن ڤێ خزمەتێ.'),
  ('city-guide-about',
   'About the Mosul Guide', 'عن دليل الموصل', 'دەربارەی ڕێنمای مووسڵ', 'دەربارەی رێنیشاندەرێ مووسلێ',
   'The Comprehensive Mosul Guide collects the places, services and offices people need across the city.',
   'دليل الموصل الشامل يجمع الأماكن والخدمات والدوائر التي يحتاجها الناس في المدينة.',
   'ڕێنمای گشتگیری مووسڵ ئەو شوێن و خزمەتگوزارییانە کۆدەکاتەوە کە خەڵک پێویستیانە.',
   'رێنیشاندەرێ گشتگیر یێ مووسلێ وان جهـ و خزمەتان کۆم دکەت یێن خەلک پێدڤی پێ نە.'),
  ('city-guide-contact',
   'Contact — Mosul Guide', 'تواصل — دليل الموصل', 'پەیوەندی — ڕێنمای مووسڵ', 'پەیوەندی — رێنیشاندەرێ مووسلێ',
   'Reach the guide team to add or correct a place. Replace this text with the phone, WhatsApp, email, address and social links for THIS section.',
   'تواصل مع فريق الدليل لإضافة مكان أو تصحيحه. استبدل هذا النص بأرقام الهاتف وواتساب والبريد والعنوان وحسابات التواصل الخاصة بهذا القسم.',
   'پەیوەندی بە تیمی ڕێنماکەوە بکە بۆ زیادکردن یان ڕاستکردنەوەی شوێنێک. ئەم دەقە بگۆڕە بە زانیاری پەیوەندی ئەم بەشە.',
   'پەیوەندی ب تیما رێنیشاندەری بکە بۆ زێدەکرن یان راستکرنا جهـەکی. ڤێ دەقێ بگوهۆرە ب زانیاریێن پەیوەندیێ یێن ڤێ بەشێ.')
ON CONFLICT (slug) DO NOTHING;

-- 2. "Product List Details" — the ten main marketplace categories the spec
--    names. The existing rows are the generic starter set from an earlier
--    migration and are left alone; staff can retire whichever they no longer
--    want from the Admin Panel, which is why these are added rather than
--    replacing the table.
INSERT INTO marketplace_categories (slug, name_en, name_ar, name_ckb, name_kmr, display_order)
VALUES
  ('electronics_appliances', 'Electronics and household appliances', 'الإلكترونيات والأجهزة المنزلية', 'ئەلیکترۆنیات و ئامێرەکانی ماڵ', 'ئەلیکترۆنیات و ئامێرێن مالێ', 20),
  ('fashion_clothing',       'Fashion and clothing',                'الأزياء والملابس',              'مۆدە و جلوبەرگ',                'مۆدە و جلک',                    21),
  ('health_beauty',          'Health and beauty',                   'الصحة والجمال',                 'تەندروستی و جوانی',             'تەندروستی و جوانی',             22),
  ('home_garden',            'Home and garden',                     'المنزل والحديقة',               'ماڵ و باخچە',                   'مال و باخچە',                   23),
  ('food_beverages',         'Food and beverages',                  'الأطعمة والمشروبات',            'خواردن و خواردنەوە',            'خوارن و ڤەخوارن',               24),
  ('sports_fitness',         'Sports and fitness',                  'الرياضة واللياقة',              'وەرزش و لەشجوانی',              'وەرزش و لەشساخی',               25),
  ('kids_baby',              'Children''s and baby products',       'منتجات الأطفال والرضّع',        'بەرهەمی منداڵ و ساوا',          'بەرهەمێن زاڕۆک و ساڤا',         26),
  ('automotive',             'Automotive supplies',                 'مستلزمات السيارات',             'پێداویستی ئۆتۆمبێل',            'پێدڤیێن ئۆتۆمبێلێ',             27),
  ('books_stationery',       'Books, library supplies and stationery', 'الكتب والقرطاسية',           'کتێب و قرتاسیە',                'کتێب و قرتاسیە',                28),
  ('industrial_tools',       'Industrial equipment and tools',      'المعدات والأدوات الصناعية',     'ئامێر و کەرەستەی پیشەسازی',     'ئامێر و کەلوپەلێن پیشەسازیێ',   29)
ON CONFLICT (slug) DO NOTHING;

-- 3. "Request contact with the person through one of the following: an
--    in-person meeting / communication through an intermediary employee / a
--    visit request."
--
--    marriage_meeting_requests carried only a message, so all three arrived
--    looking identical and staff could not tell what was being asked for.
--    Existing rows default to 'meeting', which is what the single old button
--    meant.
ALTER TABLE marriage_meeting_requests
  ADD COLUMN IF NOT EXISTS request_type VARCHAR(24) NOT NULL DEFAULT 'meeting';

-- Guard the three the app offers; anything else is a client bug, not data.
ALTER TABLE marriage_meeting_requests
  DROP CONSTRAINT IF EXISTS marriage_meeting_requests_type_check;
ALTER TABLE marriage_meeting_requests
  ADD CONSTRAINT marriage_meeting_requests_type_check
  CHECK (request_type IN ('meeting', 'intermediary', 'visit'));
