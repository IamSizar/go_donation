import { useNavigate } from 'react-router-dom'
import { ArrowLeft, ArrowRight, RotateCw, Save } from 'lucide-react'
import { useI18n } from '../lib/i18n'
import { useSaveAction } from '../lib/saveAction'

// Unified top action bar shown on every dashboard section (global notice #7).
// Back / Next use browser history; Refresh reloads the current view.
//
// F3 — Save used to dispatch a global 'app:save' event, described here as
// "a no-op on pages without a save action". It was a no-op on EVERY page: no
// listener for that event existed anywhere in admin-web/src, so the primary
// button in the fixed bar did nothing in the whole product. It now runs the
// save the page on screen registered (lib/saveAction.tsx), and is disabled
// where no page-level save exists — a list page's edits are saved from inside
// its row modal, so there is genuinely nothing here for this button to do.
//
// The page's own header renders into the slot between Refresh and Save.
//
// BUTTON ORDER (owner request): Back sits at the inline-START of the bar and
// Next at the inline-END, at opposite edges, rather than as an adjacent pair.
// "Opposite edges" is expressed by DOM ORDER inside a flex row, not by `left`
// and `right` — the dashboard renders RTL in Arabic, where the start edge is
// the right one, and a hardcoded side would put Back and Next on the wrong
// ends for every Arabic operator. Save stays immediately before Next, so it
// keeps its filled-primary prominence and its place at the action end of the
// bar while Next takes the outer edge.
//
//   [Back] [Refresh]  …page header…  [page actions] [Save] [Next]
export default function TopActionBar({
  slotRef,
  actionsRef,
  secondaryRef,
}: {
  slotRef: (el: HTMLDivElement | null) => void
  actionsRef: (el: HTMLDivElement | null) => void
  secondaryRef: (el: HTMLDivElement | null) => void
}) {
  const navigate = useNavigate()
  const { t, dir } = useI18n()
  const { save, canSave, busy } = useSaveAction()

  const refresh = () => window.location.reload()

  return (
    <div className="top-action-bar" role="toolbar" aria-label={t('common.actions')}>
      {/* Inline-START edge. `Icons.adaptive`-style mirroring: the arrow is a
          directional glyph, so it must point at the start edge in BOTH
          directions — ArrowLeft in English, ArrowRight in Arabic. Driven by
          the i18n `dir` rather than a CSS transform so the icon stays crisp
          and the DOM stays honest about what it is showing. */}
      <button
        className="secondary nav-history-btn"
        onClick={() => navigate(-1)}
        title={t('toolbar.back')}
        aria-label={t('toolbar.back')}
      >
        {dir === 'rtl' ? <ArrowRight size={15} strokeWidth={2.2} /> : <ArrowLeft size={15} strokeWidth={2.2} />}
        <span>{t('toolbar.back')}</span>
      </button>
      <button className="secondary" onClick={refresh} title={t('toolbar.refresh')}>
        <RotateCw size={15} strokeWidth={2.2} />
        <span>{t('toolbar.refresh')}</span>
      </button>
      {/* The current page's header portals in here (see PageHead), so its
          title sits next to Back/Next and its actions next to Save. When a
          page has no header this stays empty and its flex:1 acts as the
          spacer that keeps Save pinned right. */}
      <div className="page-head-slot" ref={slotRef} />
      {/* The page's primary action lands here, right next to Save. */}
      <div className="page-actions-slot" ref={actionsRef} />
      {/* Disabled rather than hidden: the client asked for the SAME four
          controls in every section, so the button keeps its place and its
          state says whether this page has anything to save. */}
      <button
        className="primary"
        onClick={save}
        disabled={!canSave || busy}
        title={t('toolbar.save')}
      >
        <Save size={15} strokeWidth={2.2} />
        <span>{busy ? t('common.saving') : t('toolbar.save')}</span>
      </button>
      {/* Inline-END edge — the far side of the bar from Back. Same directional
          mirroring: Next points at the end edge, which is the left one in
          Arabic. */}
      <button
        className="secondary nav-history-btn nav-next-btn"
        onClick={() => navigate(1)}
        title={t('toolbar.next')}
        aria-label={t('toolbar.next')}
      >
        <span>{t('toolbar.next')}</span>
        {dir === 'rtl' ? <ArrowLeft size={15} strokeWidth={2.2} /> : <ArrowRight size={15} strokeWidth={2.2} />}
      </button>
      {/* Full-width second line, so whatever a page puts here starts under
          Back rather than indented under the middle strip. Collapses to
          nothing when the page uses none of it. */}
      <div className="bar-secondary-slot" ref={secondaryRef} />
    </div>
  )
}
