// IdWithNeedsAction — the id cell of a badged list, plus the tag that says
// "this is one of the rows the sidebar number is counting".
//
// One component rather than the same JSX copied into ten pages, because the
// tag's whole value is that it means the SAME thing everywhere: an operator
// who learns it on المساهمات must be able to read it on الدعم without
// wondering whether it is a different signal. Ten copies drift.
//
// Why the tag is WORDED and not just the row's colour stripe: see the header
// of lib/needsAction.ts. Short version — nothing says what amber means, and a
// failed payment repaints a counted donation red, so colour can never be a
// reliable index of the badge.
import { fmtId, type SectionLetter } from '../lib/formatId'
import { useI18n } from '../lib/i18n'
import { needsAction, type NeedsActionTable } from '../lib/needsAction'

/**
 * The tag on its own, for the two lists whose identifier is not a plain id:
 * Sponsorships renders a sponsorshipCode(), and Registrations has no id
 * column at all and hangs it off the applicant's name. Renders nothing when
 * the row is not one the badge counts, so callers need no condition.
 */
export function NeedsActionTag({
  row,
  table,
}: {
  row: Record<string, unknown> | null | undefined
  table: NeedsActionTable
}) {
  const { t } = useI18n()
  if (!needsAction(table, row)) return null
  return (
    <span className="needs-action-tag" title={t('badge.needs_action_hint')}>
      {t('badge.needs_action')}
    </span>
  )
}

/** Which TAWAZN letter each badged list's ids carry. */
const LETTER_BY_TABLE: Record<NeedsActionTable, SectionLetter> = {
  donations: 'Z',
  sponsorships: 'Z',
  in_kind_donations: 'Z',
  beneficiary_cases: 'Z',
  beneficiary_project_requests: 'Z',
  marketplace_orders: 'N',
  marriage_profiles: 'A',
  support_tickets: 'W',
  volunteer_applications: 'W',
  volunteer_mission_signups: 'W',
  users: 'T',
}

export default function IdWithNeedsAction({
  id,
  row,
  table,
  code,
}: {
  id: number | string
  /** A short code already issued to the row (Z3, N7 …); shown instead of the raw id. */
  code?: string | null
  /** The whole row — the rule reads whichever status column its table uses. */
  row: Record<string, unknown> | null | undefined
  /** Which badge's rule applies. Keyed by the table pending_counts.go reads. */
  table: NeedsActionTable
}) {
  return (
    <span className="id-with-flag">
      <strong>{code && /^[A-Z]\d+$/.test(code) ? `\u2066#${code}\u2069` : fmtId(id, LETTER_BY_TABLE[table] ?? 'T')}</strong>
      <NeedsActionTag row={row} table={table} />
    </span>
  )
}
