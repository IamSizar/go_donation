import { useEffect, useState } from 'react'
import { Moon, Sun } from 'lucide-react'
import { useI18n } from '../lib/i18n'

import { applyTheme, type Theme } from './theme'

const KEY = 'theme'

// Dark is what the dashboard has always been, so it stays the default: no
// stored value and no data-theme attribute means dark, and the light palette
// only applies when the attribute is present (see index.css).
function stored(): Theme {
  try {
    return localStorage.getItem(KEY) === 'light' ? 'light' : 'dark'
  } catch {
    return 'dark'
  }
}

export default function ThemeToggle() {
  const { t } = useI18n()
  const [theme, setTheme] = useState<Theme>(stored)

  useEffect(() => {
    applyTheme(theme)
    try {
      localStorage.setItem(KEY, theme)
    } catch {
      // Private mode / storage disabled — the toggle still works for this
      // session, it just won't be remembered.
    }
  }, [theme])

  const next = theme === 'dark' ? 'light' : 'dark'
  return (
    <button
      type="button"
      className="secondary"
      onClick={() => setTheme(next)}
      title={t(next === 'light' ? 'theme.to_light' : 'theme.to_dark')}
      aria-label={t(next === 'light' ? 'theme.to_light' : 'theme.to_dark')}
    >
      {theme === 'dark' ? <Sun size={16} strokeWidth={2.2} /> : <Moon size={16} strokeWidth={2.2} />}
    </button>
  )
}
