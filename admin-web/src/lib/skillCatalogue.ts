// Skill catalogue — 28 canonical keys × 4 languages (en/ar/ckb/kmr).
//
// Keep in sync with:
//   - backend/internal/volunteers/catalogue.go  (server-side validator)
//   - humanitarian/lib/data/skill_catalogue.dart (mobile chips)
//
// The admin Volunteers page renders chip labels via labelFor(key, locale).
// It also exposes the flat list of keys so filter dropdowns can render
// every option even when no volunteer has that skill yet.

export type SkillCategoryKey =
  | 'transport'
  | 'trades'
  | 'medical'
  | 'service'
  | 'office'
  | 'teaching'
  | 'field'

export interface SkillEntry {
  key: string
  en: string
  ar: string
  ckb: string
  kmr: string
}

export interface SkillCategory {
  key: SkillCategoryKey
  en: string
  ar: string
  ckb: string
  kmr: string
  skills: SkillEntry[]
}

export const SKILL_CATEGORIES: SkillCategory[] = [
  {
    key: 'transport',
    en: 'Transport', ar: 'النقل', ckb: 'گواستنەوە', kmr: 'گەهاندن',
    skills: [
      { key: 'driver_car',    en: 'Car driver',        ar: 'سائق سيارة',   ckb: 'شۆفێری ئۆتۆمبێل', kmr: 'شۆفێرێ ئۆتۆمبێلێ' },
      { key: 'driver_truck',  en: 'Truck / van driver', ar: 'سائق شاحنة',   ckb: 'شۆفێری شاحنە',   kmr: 'شۆفێرێ شاحنە' },
      { key: 'motorcycle',    en: 'Motorcycle / scooter', ar: 'دراجة نارية', ckb: 'دراجە',         kmr: 'دراجە' },
    ],
  },
  {
    key: 'trades',
    en: 'Trades', ar: 'مهن', ckb: 'پیشە', kmr: 'پیشە',
    skills: [
      { key: 'electrician', en: 'Electrician',  ar: 'كهربائي', ckb: 'کارەباکار', kmr: 'کارەباکار' },
      { key: 'plumber',     en: 'Plumber',      ar: 'سبّاك',    ckb: 'لوولەکێش',  kmr: 'بۆریکێش' },
      { key: 'carpenter',   en: 'Carpenter',    ar: 'نجار',     ckb: 'دارتاش',    kmr: 'دارتاش' },
      { key: 'mason',       en: 'Mason / builder', ar: 'بنّاء',  ckb: 'بەنّا',      kmr: 'بەنا' },
      { key: 'mechanic',    en: 'Mechanic',     ar: 'ميكانيكي', ckb: 'میکانیکی',  kmr: 'میکانیکی' },
    ],
  },
  {
    key: 'medical',
    en: 'Medical', ar: 'طبي', ckb: 'پزیشکی', kmr: 'پزیشکی',
    skills: [
      { key: 'first_aid',     en: 'First aid',      ar: 'إسعافات أولية', ckb: 'یارمەتیی پێشکەش',  kmr: 'یارمەتیا پێشکەش' },
      { key: 'nurse',         en: 'Nurse',          ar: 'ممرض/ممرضة',    ckb: 'پەرستار',          kmr: 'پەرستار' },
      { key: 'doctor',        en: 'Doctor',         ar: 'طبيب',          ckb: 'پزیشک',            kmr: 'دکتۆر' },
      { key: 'mental_health', en: 'Mental health',  ar: 'دعم نفسي',      ckb: 'پشتگیری دەروونی', kmr: 'پشتگیریا دەروونی' },
      { key: 'eldercare',     en: 'Eldercare',      ar: 'رعاية المسنين', ckb: 'چاودێری بەسالان', kmr: 'چاڤدێریا بەسالان' },
    ],
  },
  {
    key: 'service',
    en: 'Service', ar: 'خدمات', ckb: 'خزمەتگوزاری', kmr: 'خزمەتگوزاری',
    skills: [
      { key: 'cook',    en: 'Cook',    ar: 'طاهٍ',   ckb: 'چێشتلێنەر', kmr: 'چێشت‌چێکەر' },
      { key: 'cleaner', en: 'Cleaner', ar: 'منظف',   ckb: 'پاککەرەوە', kmr: 'پاککەر' },
      { key: 'tailor',  en: 'Tailor',  ar: 'خياط',   ckb: 'خەیات',     kmr: 'خەیات' },
    ],
  },
  {
    key: 'office',
    en: 'Office / digital', ar: 'مكتب / رقمي', ckb: 'ئۆفیس / دیجیتاڵ', kmr: 'ئۆفیس / دیجیتاڵ',
    skills: [
      { key: 'designer',     en: 'Graphic designer', ar: 'مصمم جرافيك', ckb: 'دیزاینەری گرافیک', kmr: 'دیزاینەرێ گرافیک' },
      { key: 'photographer', en: 'Photographer',     ar: 'مصور',         ckb: 'وێنەگر',           kmr: 'وێنەگر' },
      { key: 'videographer', en: 'Videographer',     ar: 'مصور فيديو',   ckb: 'ڤیدیۆگر',          kmr: 'ڤیدیۆگر' },
      { key: 'social_media', en: 'Social media',     ar: 'تواصل اجتماعي', ckb: 'سۆشيال میدیا',   kmr: 'سۆشیال میدیا' },
      { key: 'it_support',   en: 'IT support',       ar: 'دعم تقني',     ckb: 'پشتیوانیی IT',     kmr: 'پشتگیریا IT' },
      { key: 'data_entry',   en: 'Data entry',       ar: 'إدخال البيانات', ckb: 'ناردنی داتا',   kmr: 'تۆمارکرنا داتا' },
    ],
  },
  {
    key: 'teaching',
    en: 'Teaching / language', ar: 'تعليم / لغة', ckb: 'فێرکاری / زمان', kmr: 'هیندەکاری / زمان',
    skills: [
      { key: 'teacher',         en: 'Teacher / tutor',  ar: 'معلم',          ckb: 'مامۆستا',         kmr: 'مامۆستا' },
      { key: 'translator_ar',   en: 'Arabic translator', ar: 'مترجم عربي',    ckb: 'وەرگێڕی عەرەبی',  kmr: 'وەرگێڕێ عەرەبی' },
      { key: 'translator_en',   en: 'English translator', ar: 'مترجم إنجليزي', ckb: 'وەرگێڕی ئینگلیزی', kmr: 'وەرگێڕێ ئینگلیزی' },
      { key: 'counselor',       en: 'Counselor / advisor', ar: 'مرشد',        ckb: 'ڕاوێژکار',       kmr: 'ڕاوێژکار' },
    ],
  },
  {
    key: 'field',
    en: 'Field work', ar: 'العمل الميداني', ckb: 'کاری مەیدانی', kmr: 'کارێ مەیدانی',
    skills: [
      { key: 'distribution', en: 'Aid distribution',     ar: 'توزيع المساعدات', ckb: 'دابەشکردنی یارمەتی', kmr: 'دابەشکرنا یارمەتی' },
      { key: 'survey',       en: 'Survey / assessment',  ar: 'مسح / تقييم',     ckb: 'راپرسی',             kmr: 'راپرسی' },
      { key: 'logistics',    en: 'Logistics',            ar: 'لوجستيات',        ckb: 'لۆجستی',             kmr: 'لۆجستی' },
      { key: 'warehouse',    en: 'Warehouse',            ar: 'مخزن',            ckb: 'کۆگا',               kmr: 'کۆگا' },
    ],
  },
]

/** Flat list of all 28 keys in catalogue order. */
export const ALL_SKILL_KEYS: string[] = SKILL_CATEGORIES.flatMap((c) =>
  c.skills.map((s) => s.key),
)

const skillIndex: Map<string, SkillEntry> = new Map()
for (const cat of SKILL_CATEGORIES) {
  for (const s of cat.skills) skillIndex.set(s.key, s)
}

// --- Section 13: admin-added custom professions -------------------------
// The base catalogue above is fixed in code; these are professions the admin
// adds at runtime (fetched from /api/admin/professions). Registering them lets
// skillLabelFor resolve their labels and the dropdown list them.

export interface CustomProfession {
  id: number
  skill_key: string
  category: string
  label_en: string
  label_ar: string
  label_ckb: string
  label_kmr: string
  display_order?: number
}

/** Category keys an admin may file a custom profession under: every built-in
 *  category plus the catch-all 'custom'. */
export const PROFESSION_CATEGORY_KEYS: string[] = [
  ...SKILL_CATEGORIES.map((c) => c.key),
  'custom',
]

/** Localized name for a category key (built-in categories resolve to their
 *  catalogue label; 'custom' / unknown keys fall back to the key itself). */
export function categoryLabelFor(key: string, locale: string | undefined): string {
  const cat = SKILL_CATEGORIES.find((c) => c.key === key)
  if (!cat) return key
  switch ((locale ?? 'en').toLowerCase()) {
    case 'ar': return cat.ar
    case 'ckb': return cat.ckb
    case 'kmr': return cat.kmr
    default: return cat.en
  }
}

let customSkillList: SkillEntry[] = []

/** Register admin-added professions (idempotent — replaces the previous set). */
export function registerCustomSkills(items: CustomProfession[]): void {
  customSkillList = items.map((p) => ({
    key: p.skill_key,
    en: p.label_en,
    ar: p.label_ar || p.label_en,
    ckb: p.label_ckb || p.label_en,
    kmr: p.label_kmr || p.label_en,
  }))
  for (const e of customSkillList) skillIndex.set(e.key, e)
}

/** The registered custom professions, for the dropdown's "Custom" group. */
export function getCustomSkills(): SkillEntry[] {
  return customSkillList
}

/** Pick the localized label for a single skill key. Falls back to en. */
export function skillLabelFor(key: string, locale: string | undefined): string {
  const entry = skillIndex.get(key)
  if (!entry) return key
  switch ((locale ?? 'en').toLowerCase()) {
    case 'ar': return entry.ar
    case 'ckb': return entry.ckb
    case 'kmr': return entry.kmr
    default: return entry.en
  }
}

/** Day-of-week keys aligned with backend / migration 008. */
export const DAY_KEYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const
export type DayKey = (typeof DAY_KEYS)[number]

export const DAY_LABELS: Record<DayKey, Record<string, string>> = {
  mon: { en: 'Monday',    ar: 'الإثنين',  ckb: 'دووشەممە',   kmr: 'دووشەم' },
  tue: { en: 'Tuesday',   ar: 'الثلاثاء', ckb: 'سێشەممە',    kmr: 'سێشەم' },
  wed: { en: 'Wednesday', ar: 'الأربعاء', ckb: 'چوارشەممە',  kmr: 'چوارشەم' },
  thu: { en: 'Thursday',  ar: 'الخميس',   ckb: 'پێنجشەممە',  kmr: 'پێنجشەم' },
  fri: { en: 'Friday',    ar: 'الجمعة',   ckb: 'هەینی',      kmr: 'هەینی' },
  sat: { en: 'Saturday',  ar: 'السبت',    ckb: 'شەممە',      kmr: 'شەممی' },
  sun: { en: 'Sunday',    ar: 'الأحد',    ckb: 'یەکشەممە',   kmr: 'یەکشەم' },
}

export function dayLabelFor(day: string, locale: string | undefined): string {
  const d = day.toLowerCase() as DayKey
  const row = DAY_LABELS[d]
  if (!row) return day
  return row[(locale ?? 'en').toLowerCase()] ?? row.en
}

/**
 * Localizes the day names inside the free-text `availability` summary the
 * mobile form produced — "Mon 09:00-17:00, Tue 09:00-17:00, …".
 *
 * WHY THIS EXISTS ALONGSIDE scheduleSummary()
 * scheduleSummary reads the STRUCTURED `availability_schedule` column and is
 * always the better answer, so callers try it first. But rows saved before
 * that column existed have only this English string, and on those the
 * dashboard was showing an Arabic operator seven English weekday
 * abbreviations. The comment on the old fallback said the English "cannot be
 * translated here" — that is true of arbitrary free text, and untrue of this
 * string, whose day names are a closed set of seven tokens the app itself
 * wrote.
 *
 * Only the DAY TOKENS are touched. The times are digits and separators and
 * are left exactly as stored — this rewrites nothing it does not recognise,
 * and a segment that does not match is passed through untouched rather than
 * dropped, so an unexpected format degrades to today's behaviour instead of
 * losing data.
 */
const EN_DAY_ABBREV: Record<string, DayKey> = {
  mon: 'mon', tue: 'tue', wed: 'wed', thu: 'thu', fri: 'fri', sat: 'sat', sun: 'sun',
  monday: 'mon', tuesday: 'tue', wednesday: 'wed', thursday: 'thu',
  friday: 'fri', saturday: 'sat', sunday: 'sun',
}

export function localizeAvailabilityText(
  text: string,
  locale: string | undefined,
): string {
  if (!text.trim()) return text
  let changed = false
  const out = text.split(',').map((segment) => {
    const m = /^(\s*)([A-Za-z]+)(\s.*)?$/.exec(segment)
    if (!m) return segment
    const key = EN_DAY_ABBREV[m[2].toLowerCase()]
    if (!key) return segment
    changed = true
    return `${m[1]}${dayLabelFor(key, locale)}${m[3] ?? ''}`
  })
  // Unrecognised throughout: hand back the original string rather than a
  // rebuilt copy, so nothing is subtly reformatted for no gain.
  return changed ? out.join(',') : text
}

/// A localized summary of a stored `availability_schedule`.
///
/// WHY THIS EXISTS
/// The `availability` column holds the free-text summary the mobile form
/// produced, and the form produced it with English day names — so an Arabic
/// dashboard showed "Mon 09:00-17:00, Tue …" and no amount of translating at
/// render time could fix it, because the English is already in the data.
///
/// The structured column beside it holds day KEYS, which do localize. Returns
/// '' when the schedule is missing or unusable so the caller can fall back to
/// the stored text rather than render nothing.
export function scheduleSummary(schedule: unknown, locale: string | undefined): string {
  if (!Array.isArray(schedule)) return ''
  const parts: string[] = []
  for (const entry of schedule) {
    if (!entry || typeof entry !== 'object') continue
    const row = entry as Record<string, unknown>
    const day = String(row.day ?? '')
    if (!day) continue
    const label = dayLabelFor(day, locale)
    if (label === day && !DAY_KEYS.includes(day as DayKey)) continue
    const from = String(row.from ?? '')
    const to = String(row.to ?? '')
    parts.push(from && to ? `${label} ${from}-${to}` : label)
  }
  return parts.join('، ')
}
