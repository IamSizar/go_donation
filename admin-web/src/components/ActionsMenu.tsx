// ActionsMenu — Note #4. A single "Actions" dropdown consolidating a table
// row's per-row buttons (View / Edit / Password / Archive / Delete / …)
// instead of rendering them as loose inline buttons that wrap and clutter
// the row. Reuses the same .dropdown-menu / .dropdown-menu-item styling the
// Export button uses (Note #3), so both menus look and behave identically.
import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from 'react'
import { createPortal } from 'react-dom'
import { Link } from 'react-router-dom'
import { useI18n } from '../lib/i18n'

export type ActionItem = {
  key: string
  label: string
  onClick: () => void
  // Renders in the danger (red) hover color — use for destructive actions.
  danger?: boolean
  disabled?: boolean
  // Renders as a plain link instead of a button (e.g. "View" navigating to
  // a detail page) — pass an href and onClick is ignored.
  href?: string
}

type Props = {
  items: ActionItem[]
  label?: string
}

export default function ActionsMenu({ items, label }: Props) {
  const { t } = useI18n()
  const [open, setOpen] = useState(false)
  const wrapRef = useRef<HTMLDivElement>(null)
  const btnRef = useRef<HTMLButtonElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)
  const [menuStyle, setMenuStyle] = useState<CSSProperties>({ position: 'fixed', top: 0, left: 0, visibility: 'hidden' })

  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      const target = e.target as Node
      if (wrapRef.current?.contains(target)) return
      if (menuRef.current?.contains(target)) return
      setOpen(false)
    }
    document.addEventListener('mousedown', onDocClick)
    return () => document.removeEventListener('mousedown', onDocClick)
  }, [])

  // Note #12 — the menu used to be position:absolute inside the table's own
  // overflow:auto scroll wrapper (needed for horizontal scroll on wide
  // tables — Note #1/#2). An overflow:auto ancestor clips any descendant
  // that visually escapes its box regardless of z-index, so the menu got cut
  // off near the table's edges, or rendered on top of the row below it with
  // no boundary/collision check. Render it through a portal at document.body
  // with position:fixed instead, measured against the trigger button's real
  // screen position — never clipped by an ancestor's overflow, and flips
  // above the button when there isn't room below.
  useLayoutEffect(() => {
    if (!open) return
    function place() {
      const btn = btnRef.current
      const menu = menuRef.current
      if (!btn || !menu) return
      const btnRect = btn.getBoundingClientRect()
      const menuRect = menu.getBoundingClientRect()
      const margin = 4
      const rtl = document.documentElement.dir === 'rtl'
      // Anchor to the button's "end" edge (right in LTR, left in RTL) — same
      // intent as the old insetInlineEnd:0, now computed in viewport
      // coordinates since the menu is no longer a DOM child of the button.
      let left = rtl ? btnRect.left : btnRect.right - menuRect.width
      // Clamp horizontally so it can't run off either edge of the viewport.
      left = Math.max(margin, Math.min(left, window.innerWidth - menuRect.width - margin))
      // Open downward by default; flip above the button when there isn't
      // enough room below in the viewport (e.g. a row near the table's
      // bottom edge) so it never overlaps the row(s) underneath.
      const spaceBelow = window.innerHeight - btnRect.bottom
      const openUp = spaceBelow < menuRect.height + margin && btnRect.top > menuRect.height + margin
      const top = openUp ? btnRect.top - menuRect.height - margin : btnRect.bottom + margin
      setMenuStyle({ position: 'fixed', top, left, visibility: 'visible' })
    }
    place()
    window.addEventListener('resize', place)
    // capture:true — table scroll containers don't bubble their scroll
    // events to window, but a capture-phase window listener still sees them
    // on the way down, so the menu stays anchored while the table scrolls.
    window.addEventListener('scroll', place, true)
    return () => {
      window.removeEventListener('resize', place)
      window.removeEventListener('scroll', place, true)
    }
  }, [open, items.length])

  return (
    <div ref={wrapRef} style={{ display: 'inline-block' }}>
      <button
        ref={btnRef}
        type="button"
        className="row-edit-btn"
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="menu"
        aria-expanded={open}
      >
        {label ?? t('common.actions')} <span aria-hidden="true">▾</span>
      </button>
      {open && createPortal(
        <div ref={menuRef} className="dropdown-menu" role="menu" style={menuStyle}>
          {items.map((it) =>
            it.href ? (
              <Link key={it.key} role="menuitem" className="dropdown-menu-item" to={it.href} onClick={() => setOpen(false)}>
                {it.label}
              </Link>
            ) : (
              <button
                key={it.key}
                role="menuitem"
                className={`dropdown-menu-item${it.danger ? ' danger-item' : ''}`}
                disabled={it.disabled}
                onClick={() => {
                  setOpen(false)
                  it.onClick()
                }}
              >
                {it.label}
              </button>
            ),
          )}
        </div>,
        document.body,
      )}
    </div>
  )
}
