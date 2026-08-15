// ContentSectionsEditor — K12. Manage a content page's named, ordered
// sub-sections.
//
// WHY THIS EXISTS
// "من نحن" was one free-text blob: the app renders app_content.title + body and
// nothing else, so there was no way to give the page the three named parts the
// client asked for (about the app, about the organization, about its goals),
// and no way to add a fourth later. Migration 111 adds the structure; this is
// the editor for it.
//
// It edits STRUCTURE, not content: every sub-section starts empty and the owner
// supplies the text. Nothing here invents copy.
//
// Controlled component — the parent (ContentPage) owns the list and the single
// Save, so the page and its sub-sections are saved by the same button and the
// same registered top-bar action.
//
// Plain Up/Down buttons rather than drag-and-drop, matching SidebarLayoutEditor:
// no extra dependency, keyboard-accessible, and impossible to drop in the wrong
// place. Nothing is written until Save, so Remove needs no confirmation dialog —
// leaving the page discards it.
import { ChevronDown, ChevronUp, Plus, X } from 'lucide-react'
import { useI18n } from '../lib/i18n'

/** One sub-section, in all four supported locales. Mirrors content.Section. */
export type ContentSection = {
  /** Server-assigned; absent on a row the operator just added. */
  id?: number
  /** Reported by the server; the array order is what actually saves. */
  display_order?: number
  title_en: string
  title_ar: string
  title_ckb: string
  title_kmr: string
  body_en: string
  body_ar: string
  body_ckb: string
  body_kmr: string
}

/** A blank sub-section. Empty on purpose — the owner supplies the text. */
export function emptySection(): ContentSection {
  return {
    title_en: '', title_ar: '', title_ckb: '', title_kmr: '',
    body_en: '', body_ar: '', body_ckb: '', body_kmr: '',
  }
}

/** The four locales, with the RTL flag that drives each field's `dir`. */
const LANGS: Array<{ suf: 'en' | 'ar' | 'ckb' | 'kmr'; labelKey: string; rtl: boolean }> = [
  { suf: 'en', labelKey: 'common.lang_en', rtl: false },
  { suf: 'ar', labelKey: 'common.lang_ar', rtl: true },
  { suf: 'ckb', labelKey: 'common.lang_sorani', rtl: true },
  { suf: 'kmr', labelKey: 'common.lang_badini', rtl: true },
]

type Props = {
  sections: ContentSection[]
  onChange: (next: ContentSection[]) => void
  /** True while loading or while a save is in flight. */
  disabled: boolean
}

export default function ContentSectionsEditor({ sections, onChange, disabled }: Props) {
  const { t } = useI18n()

  // ─── List operations ───────────────────────────────────────────────────

  const move = (index: number, dir: -1 | 1) => {
    const target = index + dir
    if (target < 0 || target >= sections.length) return
    const next = [...sections]
    ;[next[index], next[target]] = [next[target], next[index]]
    onChange(next)
  }

  const remove = (index: number) => onChange(sections.filter((_, i) => i !== index))

  const add = () => onChange([...sections, emptySection()])

  const setField = (index: number, key: keyof ContentSection) => (value: string) =>
    onChange(sections.map((s, i) => (i === index ? { ...s, [key]: value } : s)))

  // ─── UI ────────────────────────────────────────────────────────────────

  return (
    <div className="card stack" style={{ gap: 12 }}>
      <div>
        <h3 style={{ margin: 0 }}>{t('content.sections_title')}</h3>
        <p className="muted" style={{ marginTop: 4 }}>{t('content.sections_desc')}</p>
      </div>

      {sections.length === 0 && (
        <p className="hint">{t('content.sections_empty')}</p>
      )}

      {sections.map((section, index) => (
        <div key={section.id ?? `new-${index}`} className="card stack" style={{ gap: 10 }}>
          <div className="row" style={{ justifyContent: 'space-between' }}>
            <strong>{t('content.section_n').replace('{n}', String(index + 1))}</strong>
            <div className="row" style={{ gap: 4 }}>
              <button
                type="button"
                className="icon-btn"
                disabled={disabled || index === 0}
                onClick={() => move(index, -1)}
                title={t('common.move_up')}
                aria-label={t('common.move_up')}
              >
                <ChevronUp size={14} />
              </button>
              <button
                type="button"
                className="icon-btn"
                disabled={disabled || index === sections.length - 1}
                onClick={() => move(index, 1)}
                title={t('common.move_down')}
                aria-label={t('common.move_down')}
              >
                <ChevronDown size={14} />
              </button>
              <button
                type="button"
                className="icon-btn"
                disabled={disabled}
                onClick={() => remove(index)}
                title={t('common.remove')}
                aria-label={t('common.remove')}
              >
                <X size={14} />
              </button>
            </div>
          </div>

          {LANGS.map(({ suf, labelKey, rtl }) => (
            <div key={suf} className="stack" style={{ gap: 6 }}>
              <span className="muted">{t(labelKey)}</span>
              <label className="field">
                <span className="muted">{t('terms.field_title')}</span>
                <input
                  type="text"
                  dir={rtl ? 'rtl' : 'ltr'}
                  disabled={disabled}
                  value={section[`title_${suf}` as keyof ContentSection] as string}
                  onChange={(e) => setField(index, `title_${suf}` as keyof ContentSection)(e.target.value)}
                />
              </label>
              <label className="field">
                <span className="muted">{t('terms.field_body')}</span>
                <textarea
                  rows={5}
                  dir={rtl ? 'rtl' : 'ltr'}
                  disabled={disabled}
                  value={section[`body_${suf}` as keyof ContentSection] as string}
                  onChange={(e) => setField(index, `body_${suf}` as keyof ContentSection)(e.target.value)}
                />
              </label>
            </div>
          ))}
        </div>
      ))}

      <div className="row">
        <button type="button" className="btn" disabled={disabled} onClick={add}>
          <Plus size={14} /> {t('content.add_section')}
        </button>
      </div>
    </div>
  )
}
