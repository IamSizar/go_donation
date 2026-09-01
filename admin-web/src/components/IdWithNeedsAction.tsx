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
import { fmtId } from '../lib/formatId'
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

export default function IdWithNeedsAction({
  id,
  row,
  table,
}: {
  id: number | string
  /** The whole row — the rule reads whichever status column its table uses. */
  row: Record<string, unknown> | null | undefined
  /** Which badge's rule applies. Keyed by the table pending_counts.go reads. */
  table: NeedsActionTable
}) {
  return (
    <span className="id-with-flag">
      <strong>{fmtId(id)}</strong>
      <NeedsActionTag row={row} table={table} />
    </span>
  )
}
