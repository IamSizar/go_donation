// Skill catalogue — 28 canonical keys × 4 languages (en/ar/ckb/kmr).
//
// Keep in sync with:
//   - backend/internal/volunteers/catalogue.go (server-side validator)
//   - admin-web/src/lib/skillCatalogue.ts (admin SPA labels)
//
// The volunteer application form (proposal_services_section.dart) renders
// each category as a row of chips. The chip's key is what we send to the
// API; the label shown to the volunteer is picked by the active locale.
//
// Translations: English first as the canonical source. Arabic / Sorani /
// Badini are best-effort by a non-native speaker — review with a fluent
// volunteer coordinator before shipping if accuracy matters for a given
// region.

class SkillEntry {
  const SkillEntry({
    required this.key,
    required this.en,
    required this.ar,
    required this.ckb,
    required this.kmr,
  });

  final String key;
  final String en;
  final String ar;
  final String ckb; // Sorani
  final String kmr; // Badini

  /// Pick the label for the given locale code. Falls back to English when
  /// the locale is missing / unknown.
  String labelFor(String? localeCode) {
    switch ((localeCode ?? 'en').toLowerCase()) {
      case 'ar':
        return ar;
      case 'ckb':
      case 'ku-arab':
      case 'so':
        return ckb;
      case 'kmr':
      case 'ku-latn':
        return kmr;
      default:
        return en;
    }
  }
}

class SkillCategory {
  const SkillCategory({
    required this.key,
    required this.en,
    required this.ar,
    required this.ckb,
    required this.kmr,
    required this.skills,
  });

  final String key;
  final String en;
  final String ar;
  final String ckb;
  final String kmr;
  final List<SkillEntry> skills;

  String labelFor(String? localeCode) {
    switch ((localeCode ?? 'en').toLowerCase()) {
      case 'ar':
        return ar;
      case 'ckb':
      case 'ku-arab':
      case 'so':
        return ckb;
      case 'kmr':
      case 'ku-latn':
        return kmr;
      default:
        return en;
    }
  }
}

const List<SkillCategory> kSkillCategories = [
  SkillCategory(
    key: 'transport',
    en: 'Transport',
    ar: 'النقل',
    ckb: 'گواستنەوە',
    kmr: 'گەهاندن',
    skills: [
      SkillEntry(
        key: 'driver_car',
        en: 'Car driver',
        ar: 'سائق سيارة',
        ckb: 'شۆفێری ئۆتۆمبێل',
        kmr: 'شۆفێرێ ئۆتۆمبێلێ',
      ),
      SkillEntry(
        key: 'driver_truck',
        en: 'Truck / van driver',
        ar: 'سائق شاحنة',
        ckb: 'شۆفێری شاحنە',
        kmr: 'شۆفێرێ شاحنە',
      ),
      SkillEntry(
        key: 'motorcycle',
        en: 'Motorcycle / scooter',
        ar: 'دراجة نارية',
        ckb: 'دراجە',
        kmr: 'دراجە',
      ),
    ],
  ),
  SkillCategory(
    key: 'trades',
    en: 'Trades',
    ar: 'مهن',
    ckb: 'پیشە',
    kmr: 'پیشە',
    skills: [
      SkillEntry(
        key: 'electrician',
        en: 'Electrician',
        ar: 'كهربائي',
        ckb: 'کارەباکار',
        kmr: 'کارەباکار',
      ),
      SkillEntry(
        key: 'plumber',
        en: 'Plumber',
        ar: 'سبّاك',
        ckb: 'لوولەکێش',
        kmr: 'بۆریکێش',
      ),
      SkillEntry(
        key: 'carpenter',
        en: 'Carpenter',
        ar: 'نجار',
        ckb: 'دارتاش',
        kmr: 'دارتاش',
      ),
      SkillEntry(
        key: 'mason',
        en: 'Mason / builder',
        ar: 'بنّاء',
        ckb: 'بەنّا',
        kmr: 'بەنا',
      ),
      SkillEntry(
        key: 'mechanic',
        en: 'Mechanic',
        ar: 'ميكانيكي',
        ckb: 'میکانیکی',
        kmr: 'میکانیکی',
      ),
    ],
  ),
  SkillCategory(
    key: 'medical',
    en: 'Medical',
    ar: 'طبي',
    ckb: 'پزیشکی',
    kmr: 'پزیشکی',
    skills: [
      SkillEntry(
        key: 'first_aid',
        en: 'First aid',
        ar: 'إسعافات أولية',
        ckb: 'یارمەتیی پێشکەش',
        kmr: 'یارمەتیا پێشکەش',
      ),
      SkillEntry(
        key: 'nurse',
        en: 'Nurse',
        ar: 'ممرض/ممرضة',
        ckb: 'پەرستار',
        kmr: 'پەرستار',
      ),
      SkillEntry(
        key: 'doctor',
        en: 'Doctor',
        ar: 'طبيب',
        ckb: 'پزیشک',
        kmr: 'دکتۆر',
      ),
      SkillEntry(
        key: 'mental_health',
        en: 'Mental health',
        ar: 'دعم نفسي',
        ckb: 'پشتگیری دەروونی',
        kmr: 'پشتگیریا دەروونی',
      ),
      SkillEntry(
        key: 'eldercare',
        en: 'Eldercare',
        ar: 'رعاية المسنين',
        ckb: 'چاودێری بەسالان',
        kmr: 'چاڤدێریا بەسالان',
      ),
    ],
  ),
  SkillCategory(
    key: 'service',
    en: 'Service',
    ar: 'خدمات',
    ckb: 'خزمەتگوزاری',
    kmr: 'خزمەتگوزاری',
    skills: [
      SkillEntry(
        key: 'cook',
        en: 'Cook',
        ar: 'طاهٍ',
        ckb: 'چێشتلێنەر',
        kmr: 'چێشت‌چێکەر',
      ),
      SkillEntry(
        key: 'cleaner',
        en: 'Cleaner',
        ar: 'منظف',
        ckb: 'پاککەرەوە',
        kmr: 'پاککەر',
      ),
      SkillEntry(
        key: 'tailor',
        en: 'Tailor',
        ar: 'خياط',
        ckb: 'خەیات',
        kmr: 'خەیات',
      ),
    ],
  ),
  SkillCategory(
    key: 'office',
    en: 'Office / digital',
    ar: 'مكتب / رقمي',
    ckb: 'ئۆفیس / دیجیتاڵ',
    kmr: 'ئۆفیس / دیجیتاڵ',
    skills: [
      SkillEntry(
        key: 'designer',
        en: 'Graphic designer',
        ar: 'مصمم جرافيك',
        ckb: 'دیزاینەری گرافیک',
        kmr: 'دیزاینەرێ گرافیک',
      ),
      SkillEntry(
        key: 'photographer',
        en: 'Photographer',
        ar: 'مصور',
        ckb: 'وێنەگر',
        kmr: 'وێنەگر',
      ),
      SkillEntry(
        key: 'videographer',
        en: 'Videographer',
        ar: 'مصور فيديو',
        ckb: 'ڤیدیۆگر',
        kmr: 'ڤیدیۆگر',
      ),
      SkillEntry(
        key: 'social_media',
        en: 'Social media',
        ar: 'تواصل اجتماعي',
        ckb: 'سۆشيال میدیا',
        kmr: 'سۆشیال میدیا',
      ),
      SkillEntry(
        key: 'it_support',
        en: 'IT support',
        ar: 'دعم تقني',
        ckb: 'پشتیوانیی IT',
        kmr: 'پشتگیریا IT',
      ),
      SkillEntry(
        key: 'data_entry',
        en: 'Data entry',
        ar: 'إدخال البيانات',
        ckb: 'ناردنی داتا',
        kmr: 'تۆمارکرنا داتا',
      ),
    ],
  ),
  SkillCategory(
    key: 'teaching',
    en: 'Teaching / language',
    ar: 'تعليم / لغة',
    ckb: 'فێرکاری / زمان',
    kmr: 'هیندەکاری / زمان',
    skills: [
      SkillEntry(
        key: 'teacher',
        en: 'Teacher / tutor',
        ar: 'معلم',
        ckb: 'مامۆستا',
        kmr: 'مامۆستا',
      ),
      SkillEntry(
        key: 'translator_ar',
        en: 'Arabic translator',
        ar: 'مترجم عربي',
        ckb: 'وەرگێڕی عەرەبی',
        kmr: 'وەرگێڕێ عەرەبی',
      ),
      SkillEntry(
        key: 'translator_en',
        en: 'English translator',
        ar: 'مترجم إنجليزي',
        ckb: 'وەرگێڕی ئینگلیزی',
        kmr: 'وەرگێڕێ ئینگلیزی',
      ),
      SkillEntry(
        key: 'counselor',
        en: 'Counselor / advisor',
        ar: 'مرشد',
        ckb: 'ڕاوێژکار',
        kmr: 'ڕاوێژکار',
      ),
    ],
  ),
  SkillCategory(
    key: 'field',
    en: 'Field work',
    ar: 'العمل الميداني',
    ckb: 'کاری مەیدانی',
    kmr: 'کارێ مەیدانی',
    skills: [
      SkillEntry(
        key: 'distribution',
        en: 'Aid distribution',
        ar: 'توزيع المساعدات',
        ckb: 'دابەشکردنی یارمەتی',
        kmr: 'دابەشکرنا یارمەتی',
      ),
      SkillEntry(
        key: 'survey',
        en: 'Survey / assessment',
        ar: 'مسح / تقييم',
        ckb: 'راپرسی',
        kmr: 'راپرسی',
      ),
      SkillEntry(
        key: 'logistics',
        en: 'Logistics',
        ar: 'لوجستيات',
        ckb: 'لۆجستی',
        kmr: 'لۆجستی',
      ),
      SkillEntry(
        key: 'warehouse',
        en: 'Warehouse',
        ar: 'مخزن',
        ckb: 'کۆگا',
        kmr: 'کۆگا',
      ),
    ],
  ),
];

/// Look up a single skill by its canonical key. Used by the admin SPA when
/// rendering the chip column (key → localized label).
SkillEntry? findSkillByKey(String key) {
  for (final cat in kSkillCategories) {
    for (final s in cat.skills) {
      if (s.key == key) return s;
    }
  }
  return null;
}
