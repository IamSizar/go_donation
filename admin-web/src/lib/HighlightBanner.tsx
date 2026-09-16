// HighlightBanner.tsx — the banner that confirms where a feed click landed.
//
// Split out of useHighlightedRow.tsx because a file that exports a component
// may not also export a hook: fast refresh can only swap a module whose
// exports are all components, so mixing the two downgrades every edit of that
// file to a full page reload (react-refresh/only-export-components).

import { useI18n } from './i18n'
import { fmtId } from './formatId'
import { useHighlightedRow } from './useHighlightedRow'

// HighlightBanner — drop this at the top of a list page to confirm where the
// admin landed and offer a quick "dismiss" button. Renders nothing when there
// is no highlighted id, so it's safe to include unconditionally.
//
// `kind` is the noun shown ("Donation #11", "Sponsorship #4"). The default
// "Item" is fine but pages should pass a specific noun for clarity.
export function HighlightBanner({ kind = 'Item' }: { kind?: string }) {
  const { highlightedId, clearHighlight } = useHighlightedRow()
  const { t } = useI18n()
  if (!highlightedId) return null
  return (
    <div className="highlight-banner" role="status">
      <span className="hb-icon" aria-hidden="true">⚡</span>
      <span className="hb-text">
        <strong>{kind} {fmtId(highlightedId)}</strong>{' '}
        {t('highlight.opened_from_feed')}
      </span>
      <button type="button" onClick={clearHighlight}>{t('highlight.dismiss')}</button>
    </div>
  )
}
