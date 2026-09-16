// I18nProvider — owns the selected locale and mirrors it onto <html>.
//
// Split out of i18n.tsx so that file can keep exporting translate(), useI18n()
// and the rest without mixing them with a component export (see the note
// there). Behaviour is unchanged.

import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import {
  I18nContext,
  RTL_LOCALES,
  currentLocale,
  translate,
  type Ctx,
  type Locale,
} from './i18n'

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
