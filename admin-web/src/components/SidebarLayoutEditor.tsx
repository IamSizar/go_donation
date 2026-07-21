// SidebarLayoutEditor — Note #29 follow-up. Lets a Super-Admin reorder the
// sidebar's groups, reorder items within a group, and move an item into a
// different group (or make it standalone) — without touching code. Lives on
// Dashboard Settings; AppShell.tsx reads whatever's saved here (falling back
// to the built-in default when nothing's been customized).
//
// Deliberately uses plain Up/Down buttons + a "move to" dropdown instead of
// drag-and-drop — no extra dependency, fully keyboard-accessible, and much
// harder to get wrong than freehand dragging for a list this long (~40
// items across 7 groups + 3 standalone).
import { useEffect, useState } from 'react'
import { ChevronDown, ChevronUp } from 'lucide-react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import {
  navByTo, GROUP_DEFS, DEFAULT_NAV_SECTIONS, reconcileNavSections, type NavSection,
} from '../lib/navLayout'

const STANDALONE = '__standalone'

function swap<T>(arr: T[], i: number, j: number): T[] {
  const next = [...arr]
  ;[next[i], next[j]] = [next[j], next[i]]
  return next
}

export default function SidebarLayoutEditor() {
  const { t } = useI18n()
  const toast = useToast()
  const [sections, setSections] = useState<NavSection[]>(DEFAULT_NAV_SECTIONS)
  const [customized, setCustomized] = useState(false)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let cancelled = false
    api
      .get<{ layout: NavSection[] | null }>('/api/admin/settings/nav-layout')
      .then((r) => {
        if (cancelled) return
        setSections(reconcileNavSections(r.data.layout))
        setCustomized(!!r.data.layout)
      })
      .catch(() => { /* keep the built-in default */ })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [])

  function moveSection(index: number, dir: -1 | 1) {
    const target = index + dir
    if (target < 0 || target >= sections.length) return
    setSections((s) => swap(s, index, target))
  }

  function moveItemInGroup(sectionIndex: number, itemIndex: number, dir: -1 | 1) {
    setSections((s) => {
      const section = s[sectionIndex]
      if (section.kind !== 'group') return s
      const target = itemIndex + dir
      if (target < 0 || target >= section.items.length) return s
      const next = [...s]
      next[sectionIndex] = { ...section, items: swap(section.items, itemIndex, target) }
      return next
    })
  }

  // Removes `to` from wherever it currently lives, then either drops it into
  // an existing group with that key, creates a fresh single-item group if
  // none exists yet (a group can disappear from `sections` once emptied),
  // or appends a new standalone item section.
  function moveItemToGroup(to: string, targetKey: string) {
    setSections((s) => {
      let without = s
        .map((sec) => (sec.kind === 'group' ? { ...sec, items: sec.items.filter((x) => x !== to) } : sec))
        .filter((sec) => sec.kind === 'item' ? sec.to !== to : sec.items.length > 0)

      if (targetKey === STANDALONE) {
        return [...without, { kind: 'item', to }]
      }
      const existing = without.find((sec) => sec.kind === 'group' && sec.key === targetKey)
      if (existing && existing.kind === 'group') {
        without = without.map((sec) =>
          sec === existing ? { ...sec, items: [...sec.items, to] } : sec,
        )
        return without
      }
      const def = GROUP_DEFS.find((g) => g.key === targetKey)
      if (!def) return without
      return [...without, { kind: 'group', key: def.key, tKey: def.tKey, items: [to] }]
    })
  }

  async function save() {
    setSaving(true)
    try {
      await api.put('/api/admin/settings/nav-layout', { layout: sections })
      setCustomized(true)
      toast.success(t('settings.saved'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSaving(false)
    }
  }

  async function resetToDefault() {
    setSaving(true)
    try {
      await api.put('/api/admin/settings/nav-layout', { layout: null })
      setSections(DEFAULT_NAV_SECTIONS)
      setCustomized(false)
      toast.success(t('settings.sidebar_layout_reset_ok'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSaving(false)
    }
  }

  if (loading) return null

  return (
    <div className="card stack" style={{ gap: 12 }}>
      <div>
        <h3 style={{ margin: 0 }}>{t('settings.sidebar_layout_title')}</h3>
        <p className="muted" style={{ marginTop: 4 }}>{t('settings.sidebar_layout_desc')}</p>
      </div>

      <div className="stack" style={{ gap: 6 }}>
        {sections.map((section, sIdx) => (
          <div key={section.kind === 'item' ? section.to : section.key} className="sidebar-layout-section">
            <div className="sidebar-layout-row">
              <div className="sidebar-layout-updown">
                <button
                  type="button" className="icon-btn" disabled={sIdx === 0}
                  onClick={() => moveSection(sIdx, -1)} title={t('settings.sidebar_layout_move_up')}
                >
                  <ChevronUp size={14} />
                </button>
                <button
                  type="button" className="icon-btn" disabled={sIdx === sections.length - 1}
                  onClick={() => moveSection(sIdx, 1)} title={t('settings.sidebar_layout_move_down')}
                >
                  <ChevronDown size={14} />
                </button>
              </div>
              <strong>
                {section.kind === 'item' ? t(navByTo.get(section.to)?.tKey ?? section.to) : t(section.tKey)}
              </strong>
              {section.kind === 'group' && (
                <span className="muted" style={{ fontSize: 12 }}>
                  {t('settings.sidebar_layout_item_count', { n: section.items.length })}
                </span>
              )}
            </div>

            {section.kind === 'group' && (
              <div className="sidebar-layout-items">
                {section.items.map((to, iIdx) => {
                  const item = navByTo.get(to)
                  if (!item) return null
                  return (
                    <div key={to} className="sidebar-layout-row sidebar-layout-item">
                      <div className="sidebar-layout-updown">
                        <button
                          type="button" className="icon-btn" disabled={iIdx === 0}
                          onClick={() => moveItemInGroup(sIdx, iIdx, -1)} title={t('settings.sidebar_layout_move_up')}
                        >
                          <ChevronUp size={12} />
                        </button>
                        <button
                          type="button" className="icon-btn" disabled={iIdx === section.items.length - 1}
                          onClick={() => moveItemInGroup(sIdx, iIdx, 1)} title={t('settings.sidebar_layout_move_down')}
                        >
                          <ChevronDown size={12} />
                        </button>
                      </div>
                      <span>{t(item.tKey)}</span>
                      <select
                        value={section.key}
                        onChange={(e) => moveItemToGroup(to, e.target.value)}
                        aria-label={t('settings.sidebar_layout_move_to', { item: t(item.tKey) })}
                      >
                        {GROUP_DEFS.map((g) => (
                          <option key={g.key} value={g.key}>{t(g.tKey)}</option>
                        ))}
                        <option value={STANDALONE}>{t('settings.sidebar_layout_standalone')}</option>
                      </select>
                    </div>
                  )
                })}
              </div>
            )}
            {section.kind === 'item' && (
              <div className="sidebar-layout-items">
                <div className="sidebar-layout-row sidebar-layout-item">
                  <span className="muted" style={{ fontSize: 12 }}>{t('settings.sidebar_layout_standalone')}</span>
                  <select
                    value={STANDALONE}
                    onChange={(e) => moveItemToGroup(section.to, e.target.value)}
                    aria-label={t('settings.sidebar_layout_move_to', { item: t(navByTo.get(section.to)?.tKey ?? section.to) })}
                  >
                    <option value={STANDALONE}>{t('settings.sidebar_layout_standalone')}</option>
                    {GROUP_DEFS.map((g) => (
                      <option key={g.key} value={g.key}>{t(g.tKey)}</option>
                    ))}
                  </select>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>

      <div className="row" style={{ gap: 8 }}>
        <button onClick={save} disabled={saving}>
          {saving ? t('common.saving') : t('common.save')}
        </button>
        {customized && (
          <button className="secondary" onClick={resetToDefault} disabled={saving}>
            {t('settings.sidebar_layout_reset')}
          </button>
        )}
      </div>
    </div>
  )
}
