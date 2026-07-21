// iraqGovernorates — Note #32. Fixed list of Iraq's 18 governorates, used to
// turn the beneficiary case form's free-text "City" field into a structured
// dropdown ("Governorate" per the client's note) instead of open text. No
// canonical governorate/city/neighborhood table exists anywhere in the
// schema, so this is a static list rather than an API-fetched one — the
// underlying `city` DB column/API field is unchanged, only its label and
// input widget change.
export type Governorate = { value: string; en: string; ar: string }

export const IRAQ_GOVERNORATES: Governorate[] = [
  { value: 'baghdad', en: 'Baghdad', ar: 'بغداد' },
  { value: 'basra', en: 'Basra', ar: 'البصرة' },
  { value: 'nineveh', en: 'Nineveh', ar: 'نينوى' },
  { value: 'erbil', en: 'Erbil', ar: 'أربيل' },
  { value: 'sulaymaniyah', en: 'Sulaymaniyah', ar: 'السليمانية' },
  { value: 'duhok', en: 'Duhok', ar: 'دهوك' },
  { value: 'kirkuk', en: 'Kirkuk', ar: 'كركوك' },
  { value: 'najaf', en: 'Najaf', ar: 'النجف' },
  { value: 'karbala', en: 'Karbala', ar: 'كربلاء' },
  { value: 'anbar', en: 'Anbar', ar: 'الأنبار' },
  { value: 'diyala', en: 'Diyala', ar: 'ديالى' },
  { value: 'wasit', en: 'Wasit', ar: 'واسط' },
  { value: 'saladin', en: 'Saladin', ar: 'صلاح الدين' },
  { value: 'babil', en: 'Babil', ar: 'بابل' },
  { value: 'qadisiyyah', en: 'Al-Qadisiyyah', ar: 'القادسية' },
  { value: 'muthanna', en: 'Al-Muthanna', ar: 'المثنى' },
  { value: 'dhi_qar', en: 'Dhi Qar', ar: 'ذي قار' },
  { value: 'maysan', en: 'Maysan', ar: 'ميسان' },
]

export function governorateLabel(value: string | null | undefined, locale: string | undefined): string {
  if (!value) return ''
  const g = IRAQ_GOVERNORATES.find((x) => x.value === value)
  if (!g) return value
  return locale === 'ar' || locale === 'ckb' || locale === 'kmr' ? g.ar : g.en
}
