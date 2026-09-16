// theme.ts — applying the dashboard's light/dark palette to <html>.
//
// Split out of ThemeToggle.tsx because a file that exports a component may not
// also export functions: Vite's fast refresh can only swap a module whose
// exports are all components (react-refresh/only-export-components).

export type Theme = 'dark' | 'light'

/** Applied before React mounts too — see the inline script in index.html — so
 *  a light-theme user doesn't get a dark flash on every page load. */
export function applyTheme(theme: Theme) {
  if (theme === 'light') document.documentElement.setAttribute('data-theme', 'light')
  else document.documentElement.removeAttribute('data-theme')
}
