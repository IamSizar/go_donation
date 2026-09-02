// Picking the reader's language out of a row that carries several.
//
// WHY THIS EXISTS
// Content tables keep one column per language — `public_title`,
// `public_title_ar`, `public_title_sorani`, `public_title_badini` — and the
// API sends all of them. Screens then picked one by hand, and several picked
// the English one: the case picker in the volunteer board listed
// "CSE-DEMO-0002 — Displaced family struggling to afford food" to an operator
// working entirely in Arabic, even though the Arabic title was sitting in the
// same object.
//
// Two other places had already written this by hand — BeneficiaryPage's
// `byLocale` map and VolunteersPage's chain of ternaries — which is how the
// third one came to be missed. One helper, used everywhere, is the shape that
// stops a fourth.
//
// FALLING BACK IS THE POINT
// A translation column is nullable and usually empty: staff enter the title in
// one language and the others are filled in later, if ever. So an empty Arabic
// title must fall through to something readable rather than render a blank
// row — showing the English title is a worse outcome than showing nothing only
// in theory, and in practice an operator needs to identify the case.

/** The locale suffixes used by the content tables, in fallback order. */
const SUFFIX: Record<string, readonly string[]> = {
  // Arabic first for Kurdish readers: the Kurdish columns are the least
  // complete, and Arabic is far likelier to be present and readable to them
  // than English is.
  ckb: ['_sorani', '_ar', ''],
  kmr: ['_badini', '_ar', ''],
  ar: ['_ar', ''],
  en: [''],
}

/**
 * The value of `field` in the reader's language, falling back through the
 * chain above to the base (English) column.
 *
 * `row` is deliberately loose: this is called with cases, campaigns, missions
 * and city places, which share the convention but not a type.
 */
export function localizedField(
  row: Record<string, unknown> | null | undefined,
  field: string,
  locale: string | undefined,
): string {
  if (!row) return ''
  const chain = SUFFIX[(locale ?? 'en').toLowerCase()] ?? SUFFIX.en
  for (const suffix of chain) {
    const value = row[`${field}${suffix}`]
    if (typeof value === 'string' && value.trim() !== '') return value
  }
  return ''
}

/**
 * "CSE-000123 — عنوان الحالة", or just the code when no title survives the
 * fallback.
 *
 * The code stays Latin on purpose: it is an identifier printed on paperwork
 * and searched for character by character, not a word to translate.
 */
export function caseLabel(
  row: Record<string, unknown> | null | undefined,
  locale: string | undefined,
): string {
  if (!row) return ''
  const code = typeof row.case_code === 'string' ? row.case_code : ''
  const title = localizedField(row, 'public_title', locale)
  if (!code) return title
  return title ? `${code} — ${title}` : code
}

/**
 * The two lines a content LIST cell shows: the reader's language on top, and
 * whatever other version exists underneath.
 *
 * WHY THE ORDER MATTERS, AND WHY IT WAS WRONG
 * Nine list pages were written as `<strong>{row.title}</strong>` with
 * `{row.title_ar}` muted beneath it. That is the English column first,
 * regardless of the language the operator chose — so an Arabic dashboard
 * showed "Marketplace order submitted" in bold with the Arabic as a grey
 * footnote. Whole screens read as English with Arabic annotations.
 *
 * The secondary line is KEPT rather than dropped: this is a content-management
 * table, and staff editing translations need to see the source next to the
 * translation. It is only shown when it differs from the primary, so a row
 * that exists in one language does not print the same string twice.
 */
export function localizedPair(
  row: Record<string, unknown> | null | undefined,
  field: string,
  locale: string | undefined,
): { primary: string; secondary: string } {
  const primary = localizedField(row, field, locale)
  const base = row && typeof row[field] === 'string' ? (row[field] as string) : ''
  // The Arabic column is the useful companion for a Kurdish reader, for the
  // same reason it comes before English in the fallback chain above.
  const companionField = (locale ?? 'en').toLowerCase() === 'en' ? `${field}_ar` : field
  const companion =
    row && typeof row[companionField] === 'string' ? (row[companionField] as string) : base
  const secondary = companion.trim() && companion.trim() !== primary.trim() ? companion : ''
  return { primary: primary || base, secondary }
}
