// i18n — Phase 19 lightweight in-app translation hook.
//
// Why custom: react-i18next pulls in ~30 KB and its full feature set
// (plurals, namespaces, suspense) is not needed here. We have 4 locales,
// flat key paths, and simple {var} interpolation. ~70 lines of code.
//
// Usage:
//
//   const { t, locale, setLocale } = useI18n()
//   t('nav.dashboard')                 // "Dashboard" / "لوحة التحكم" / ...
//   t('toast.saved', { name: 'Sizar' }) // "Sizar saved"
//
// The selected locale is persisted to localStorage and applied to
// document.documentElement.dir on every change so RTL flips happen at
// the root.

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import en from './locales/en'
import ar from './locales/ar'
import ckb from './locales/ckb'
import kmr from './locales/kmr'

export type Locale = 'en' | 'ar' | 'ckb' | 'kmr'

export const LOCALES: { code: Locale; label: string; nativeLabel: string }[] = [
  { code: 'en',  label: 'English', nativeLabel: 'English' },
  { code: 'ar',  label: 'Arabic',  nativeLabel: 'العربية' },
  { code: 'ckb', label: 'Sorani',  nativeLabel: 'سۆرانی' },
  { code: 'kmr', label: 'Badini',  nativeLabel: 'بادینی' },
]

// Keep these as one shape — types ensure all locales export the same key tree.
export type MessageTree = typeof en
// en is the full canonical tree; ar/ckb/kmr are DeepPartial (string leaves,
// optional keys), so the map is typed loosely. dig() reads it as `unknown`
// and falls back to en for any key a locale doesn't define.
const messages: Record<Locale, unknown> = { en, ar, ckb, kmr }

const RTL_LOCALES: Locale[] = ['ar', 'ckb', 'kmr']

type Ctx = {
  locale: Locale
  setLocale: (l: Locale) => void
  // t looks up a dotted key and interpolates {var} placeholders.
  // Missing keys fall back to the English message; missing in English too
  // returns the key itself so we can spot it visually in the UI.
  t: (key: string, vars?: Record<string, string | number>) => string
  dir: 'ltr' | 'rtl'
}

const I18nContext = createContext<Ctx | null>(null)

// Look up a dotted path inside a nested message tree.
function dig(tree: unknown, parts: string[]): unknown {
  let cur: unknown = tree
  for (const p of parts) {
    if (cur && typeof cur === 'object' && p in (cur as Record<string, unknown>)) {
      cur = (cur as Record<string, unknown>)[p]
    } else {
      return undefined
    }
  }
  return cur
}

function interpolate(template: string, vars?: Record<string, string | number>): string {
  if (!vars) return template
  return template.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? String(vars[k]) : m))
}

// currentLocale — hook-free accessor for non-React code paths (the CSV/Excel/
// PDF export builders in lib/csv.ts). Reads the same persisted value the
// provider syncs to localStorage; safe because exports run on a user click,
// long after the provider has written the current locale.
export function currentLocale(): Locale {
  const stored = localStorage.getItem('locale')
  if (stored === 'en' || stored === 'ar' || stored === 'ckb' || stored === 'kmr') return stored
  return 'en'
}

// translate — hook-free t(). Same resolution as the provider's t: selected
// locale → English fallback → the key itself.
export function translate(
  key: string,
  vars?: Record<string, string | number>,
  locale: Locale = currentLocale(),
): string {
  const parts = key.split('.')
  let v = dig(messages[locale], parts)
  if (typeof v !== 'string') v = dig(messages.en, parts)
  if (typeof v !== 'string') return key
  return interpolate(v, vars)
}

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(() => currentLocale())

  const dir: 'ltr' | 'rtl' = RTL_LOCALES.includes(locale) ? 'rtl' : 'ltr'

  // Mirror to <html dir> so descendants inherit direction.
  useEffect(() => {
    document.documentElement.dir = dir
    document.documentElement.lang = locale
  }, [dir, locale])

  const setLocale = useCallback((l: Locale) => {
    setLocaleState(l)
    localStorage.setItem('locale', l)
  }, [])

  const t = useCallback<Ctx['t']>((key, vars) => translate(key, vars, locale), [locale])

  const value = useMemo<Ctx>(() => ({ locale, setLocale, t, dir }), [locale, setLocale, t, dir])
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}

export function useI18n(): Ctx {
  const c = useContext(I18nContext)
  if (!c) throw new Error('useI18n must be used inside <I18nProvider>')
  return c
}

// useStatusLabel — resolves a status/enum machine value (e.g. 'in_progress')
// to its localized label via the `status.*` namespace. Unknown values fall
// back to the raw string so a new backend status never renders as a key.
// The value sent back to the API is always the raw machine string; only the
// DISPLAY is localized.
export function useStatusLabel(): (value: string) => string {
  const { t } = useI18n()
  return (value: string) => {
    const key = `status.${value}`
    const label = t(key)
    return label === key ? value : label
  }
}

// useFieldLabel — localizes a raw DB column key (e.g. 'created_at', 'title_ar')
// for the read-only Detail view and Audit Logs. It strips a trailing language
// suffix (_ar/_sorani/_badini/_en) and appends a language tag, then resolves
// the base via dbfield.* → col.* → field.*. Falls back to the raw key only when
// nothing matches (so a brand-new column never renders as a bare i18n key).
const LANG_TAG: Record<string, string> = {
  ar: 'lang_ar', sorani: 'lang_sorani', badini: 'lang_badini', en: 'lang_en',
}
// fieldLabelFor — hook-free version of the same resolution, shared by the
// hook below and the export builders (lib/csv.ts). Pass a t function to bind
// it to React state; defaults to the localStorage-backed translate().
export function fieldLabelFor(
  key: string,
  tr: (k: string) => string = (k) => translate(k),
): string {
  let base = key
  let suffix = ''
  const m = key.match(/^(.*)_(ar|sorani|badini|en)$/)
  if (m && LANG_TAG[m[2]]) {
    base = m[1]
    suffix = ` (${tr('common.' + LANG_TAG[m[2]])})`
  }
  for (const ns of ['dbfield.', 'col.', 'field.']) {
    const label = tr(ns + base)
    if (label !== ns + base) return label + suffix
  }
  return key
}
export function useFieldLabel(): (key: string) => string {
  const { t } = useI18n()
  return (key: string) => fieldLabelFor(key, t)
}
