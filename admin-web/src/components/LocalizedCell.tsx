/**
 * A content list cell that reads in the operator's language.
 *
 * WHY IT EXISTS
 * Nine list pages were written as `<strong>{row.title}</strong>` with
 * `{row.title_ar}` muted underneath — the English column first, whatever
 * language the dashboard was in. An Arabic operator got "Marketplace order
 * submitted" in bold with the Arabic as a grey footnote, on screen after
 * screen. The owner's report was simply that English keeps showing up inside
 * the Arabic dashboard, and this was most of it.
 *
 * The second line is kept, not dropped: these are content-management tables,
 * and staff filling in translations need the source beside the translation.
 * It only appears when it differs from the first, so a row that exists in one
 * language does not print the same string twice.
 */
import { localizedPair } from '../lib/localizedContent'

export default function LocalizedCell({
  row,
  field,
  locale,
  dir,
}: {
  /** The row itself; these tables share the column convention, not a type. */
  row: unknown
  /** Base column name, e.g. 'title' — the suffixed ones are derived. */
  field: string
  /** The dashboard's active locale. */
  locale: string | undefined
  /** Set on the secondary line where a page already forced a direction. */
  dir?: 'rtl' | 'ltr'
}) {
  const { primary, secondary } = localizedPair(
    row as Record<string, unknown>,
    field,
    locale,
  )
  return (
    <div className="cell-stack">
      <strong>{primary}</strong>
      {secondary && (
        <span className="muted" dir={dir}>
          {secondary}
        </span>
      )}
    </div>
  )
}
