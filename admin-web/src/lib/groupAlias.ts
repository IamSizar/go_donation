/**
 * groupAlias.ts — shows a server-generated masked label ("Donor 1") in the
 * dashboard's language ("مانح 1").
 *
 * The server writes masked-group labels in English (chatgroups autoLabel) and
 * translates them only on the way out to members (backend
 * notify/group_alias.go, and the app's chat bubbles). The dashboard showed the
 * raw English inside the Arabic UI. Same anchored pattern as the server, so a
 * label staff typed by hand is never rewritten.
 */
import type { Locale } from './i18n'

const SERVER_ALIAS = /^(Donor|Beneficiary|Volunteer|Member) ([1-9][0-9]*)$/

const NOUNS: Record<string, Partial<Record<Locale, string>>> = {
  Donor: { ar: 'مانح', ckb: 'بەخشەر', kmr: 'بەخشەر' },
  Beneficiary: { ar: 'مستحق', ckb: 'وەرگری شایستە', kmr: 'وەرگرێ شایستە' },
  Volunteer: { ar: 'متطوع', ckb: 'خۆبەخش', kmr: 'خۆبەخش' },
  Member: { ar: 'عضو' },
}

export function localizeGroupAlias(label: string, locale: Locale): string {
  const m = SERVER_ALIAS.exec(label)
  if (!m) return label
  const word = NOUNS[m[1]]?.[locale]
  return word ? `${word} ${m[2]}` : label
}
