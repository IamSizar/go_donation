-- 025_app_content.sql — editable static content pages (Terms & Conditions now;
-- reusable for About/Contact later). One row per slug, title+body in all 4 langs.
-- Public GET /api/content/:slug renders it; admin PUT /api/admin/content/:slug edits it.

CREATE TABLE IF NOT EXISTS app_content (
  slug        VARCHAR(48) PRIMARY KEY,
  title_en    TEXT      NOT NULL DEFAULT '',
  title_ar    TEXT      NOT NULL DEFAULT '',
  title_ckb   TEXT      NOT NULL DEFAULT '',
  title_kmr   TEXT      NOT NULL DEFAULT '',
  body_en     TEXT      NOT NULL DEFAULT '',
  body_ar     TEXT      NOT NULL DEFAULT '',
  body_ckb    TEXT      NOT NULL DEFAULT '',
  body_kmr    TEXT      NOT NULL DEFAULT '',
  updated_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by  BIGINT
);

-- Seed a DRAFT Terms & Conditions (admin should review & edit the final text).
INSERT INTO app_content (slug, title_en, title_ar, title_ckb, title_kmr, body_en, body_ar, body_ckb, body_kmr)
VALUES (
  'terms',
  'Terms & Conditions',
  'الشروط والأحكام',
  'مەرج و ڕێساکان',
  'مەرج و رێسا',
  $tc$Welcome to BalanceNex. By creating an account or using this app, you agree to these Terms & Conditions.

1. Purpose — BalanceNex is a humanitarian platform that connects grantors, eligible persons and volunteers to organize and deliver aid.

2. Accounts — You agree to provide accurate information. Accounts and submitted data are reviewed by our team before activation.

3. Giving & Aid — Contributions are directed to eligible cases as described in the app. We are not responsible for delays caused by third parties.

4. Conduct — You agree to use the app lawfully and respectfully, and not to misuse other users' data.

5. Privacy — Your data is handled according to our privacy practices; identification codes are used to hide explicit names where possible.

6. Changes — These terms may be updated from time to time. Continued use of the app means you accept the current terms.

7. Contact — For any questions, please use the in-app support.

(This is an initial draft. Please review and edit the final text from the admin dashboard.)$tc$,
  $tc$مرحباً بك في BalanceNex. بإنشائك حساباً أو باستخدامك هذا التطبيق فإنك توافق على هذه الشروط والأحكام.

1. الغرض — BalanceNex منصة إنسانية تربط المانحين والمستحقين والمتطوعين لتنظيم المساعدات وإيصالها.

2. الحسابات — تلتزم بتقديم معلومات صحيحة. تُراجَع الحسابات والبيانات المُرسَلة من قِبَل فريقنا قبل التفعيل.

3. العطاء والمساعدة — تُوجَّه المساهمات إلى الحالات المستحقة كما هو موضّح في التطبيق. لسنا مسؤولين عن أي تأخير يسببه طرف ثالث.

4. السلوك — تلتزم باستخدام التطبيق بشكل قانوني ومحترم وعدم إساءة استخدام بيانات المستخدمين الآخرين.

5. الخصوصية — تُعالَج بياناتك وفق ممارسات الخصوصية لدينا، وتُستخدَم رموز تعريفية لإخفاء الأسماء الصريحة قدر الإمكان.

6. التغييرات — قد تُحدَّث هذه الشروط من حين لآخر، واستمرارك في استخدام التطبيق يعني قبولك للشروط الحالية.

7. التواصل — لأي استفسار، يُرجى استخدام الدعم داخل التطبيق.

(هذه مسودة أولية. يُرجى مراجعة النص النهائي وتحريره من لوحة الإدارة.)$tc$,
  $tc$بەخێربێیت بۆ BalanceNex. بە دروستکردنی هەژمار یان بەکارهێنانی ئەم ئەپە، تۆ ڕازیت بەم مەرج و ڕێساکان.

١. مەبەست — BalanceNex سەکۆیەکی مرۆییە کە بەخشەران و مستحقان و خۆبەخشان بەیەکەوە دەبەستێتەوە بۆ ڕێکخستن و گەیاندنی یارمەتی.

٢. هەژمارەکان — پابەندیت بە پێدانی زانیاری ڕاست. هەژمار و داتای نێردراو لەلایەن تیمەکەمانەوە پێداچوونەوەیان بۆ دەکرێت پێش چالاککردن.

٣. بەخشین و یارمەتی — بەخشینەکان بۆ کەیسە مستحقەکان ئاراستە دەکرێن وەک لە ئەپەکەدا باسکراوە. بەرپرس نین لە هیچ دواکەوتنێک کە لایەنی سێیەم دروستی دەکات.

٤. ڕەفتار — پابەندیت بە بەکارهێنانی ئەپەکە بە شێوەیەکی یاسایی و ڕێزدارانە و خراپ بەکارنەهێنانی داتای بەکارهێنەرانی تر.

٥. تایبەتمەندی — داتاکەت بەپێی ڕێساکانی تایبەتمەندیمان مامەڵەی لەگەڵ دەکرێت، و کۆدی ناسێنەر بەکاردەهێنرێت بۆ شاردنەوەی ناوی ڕوون تا ئەو ئەندازەیەی دەکرێت.

٦. گۆڕانکاری — لەوانەیە ئەم مەرجانە جار لە جار نوێ بکرێنەوە، بەردەوامبوون لە بەکارهێنان واتە قبوڵکردنی مەرجە ئێستاکان.

٧. پەیوەندی — بۆ هەر پرسیارێک، تکایە پشتگیری ناو ئەپەکە بەکاربهێنە.

(ئەمە ڕەشنووسێکی سەرەتاییە. تکایە دەقی کۆتایی لە داشبۆردی بەڕێوەبەریەوە پێداچوونەوە و دەستکاری بکە.)$tc$,
  $tc$بەخێربێی بۆ BalanceNex. ب چێکرنا هەژمارەکێ یان ب بکارئینانا ڤێ ئەپێ، تو رازی دبی ب ڤان مەرج و رێسایان.

١. ئارمانج — BalanceNex پلاتفۆرمەکا مرۆڤایەتییە یا کو بەخشەران و مستحقان و خۆبەخشان گرێدەدەت بۆ رێکخستن و گەهاندنا هاریکاریێ.

٢. هەژمار — تو پابەندی ب دانا زانیاریێن راست. هەژمار و داتایێن هاتینە شاندن ژلایێ تیما مە ڤە تێنە پشکنین بەری چالاککرنێ.

٣. بەخشین و هاریکاری — بەخشین بۆ حالەتێن مستحق تێنە ئاراستەکرن وەک ل ئەپێ هاتیە دیارکرن. ئەم بەرپرس نینن ژ هەر دواکەفتنەکێ یێ کو لایەنێ سێیەم چێدکەت.

٤. رەفتار — تو پابەندی ب بکارئینانا ئەپێ ب رێکا یاسایی و رێزداری و خراب بکارنەئینانا داتایێن بکارهێنەرێن دی.

٥. تایبەتی — داتایێن تە ل گۆرەی رێسایێن تایبەتیا مە تێنە بریڤەبرن، و کۆدێن ناسینێ تێنە بکارئینان بۆ ڤەشارتنا ناڤێن ئاشکەرا تا رادەیەکێ.

٦. گهۆرین — دبیت ڤان مەرجان جار ب جار بێنە نویکرن، بەردەوامی د بکارئینانێ دا واتە قبوولکرنا مەرجێن نوکە.

٧. پەیوەندی — بۆ هەر پرسیارەکێ، ژ کەرەما خۆ پشتگیریا ناڤ ئەپێ بکاربینە.

(ئەڤە پێشنڤیسەکا سەرەتایییە. ژ کەرەما خۆ دەقێ داوی ژ داشبۆردا بەرپرسیارییێ پشکنین و دەستکاری بکە.)$tc$
)
ON CONFLICT (slug) DO NOTHING;
