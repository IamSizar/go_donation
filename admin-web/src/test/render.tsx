/**
 * render.tsx — renderWithProviders(), the one way tests mount app UI.
 *
 * WHAT IT PROVIDES
 * The providers a page or component expects from App.tsx, in App.tsx's order:
 * a router, i18n, the dialog host (lib/api.ts raises the delete-password
 * dialog through it), auth, and toasts. It also seeds what those providers
 * read when they mount: a signed-in staff session and the interface locale.
 *
 * WHAT IT DELIBERATELY LEAVES OUT
 * PendingCountsProvider and GlobalAlertsProvider. Both start a 5-second
 * polling timer the moment they mount, which would make every test depend on
 * real timers and send requests the test never registered. A test for
 * something that needs one of them wraps it itself. usePendingCounts() has a
 * default context value, so a component that only reads the counts renders
 * without the provider.
 *
 * The session is seeded through lib/api.ts's own setToken/setStoredUser rather
 * than by writing its storage keys here, so a renamed key cannot leave the
 * tests signed in somewhere the app no longer looks. The locale has no
 * hook-free setter, so its key ('locale', read by currentLocale() in
 * lib/i18n.tsx) is written directly.
 */
import type { ReactElement } from 'react'
import { render, type RenderResult } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { setStoredUser, setToken, type StoredUser } from '../lib/api'
import { AuthProvider } from '../lib/AuthProvider'
import { DialogHost } from '../lib/DialogHost'
import { I18nProvider } from '../lib/I18nProvider'
import type { Locale } from '../lib/i18n'
import { ToastProvider } from '../lib/ToastProvider'
import { MOCK_STAFF_USER, MOCK_TOKEN } from './fixtures/session'

/** Options for {@link renderWithProviders}. Every field is optional. */
export type RenderOptions = {
  /** The URL the router starts at. Defaults to '/'. */
  route?: string
  /**
   * The route pattern `ui` is mounted under, e.g. 'detail/:resource/:id', so
   * useParams() resolves. Defaults to '*', which matches any URL.
   */
  path?: string
  /**
   * The signed-in staff member. Defaults to the super_admin
   * {@link MOCK_STAFF_USER}; pass null to render signed out.
   */
  user?: StoredUser | null
  /** The interface language. Defaults to 'en'. */
  locale?: Locale
}

/**
 * Renders `ui` inside the app's providers: signed in as a super_admin and in
 * English unless the options say otherwise.
 *
 * @param ui       the component or page under test.
 * @param options  starting route, route pattern, signed-in user and locale;
 *                 see {@link RenderOptions}.
 * @returns        Testing Library's render result (container, rerender,
 *                 unmount and the bound queries).
 */
export function renderWithProviders(ui: ReactElement, options: RenderOptions = {}): RenderResult {
  const { route = '/', path = '*', user = MOCK_STAFF_USER, locale = 'en' } = options

  // Seeded BEFORE render: I18nProvider and AuthProvider read these in their
  // useState initialisers, so a value written after mounting would be ignored.
  localStorage.setItem('locale', locale)
  setToken(user ? MOCK_TOKEN : null)
  setStoredUser(user)

  return render(
    <MemoryRouter initialEntries={[route]}>
      <I18nProvider>
        <DialogHost />
        <AuthProvider>
          <ToastProvider>
            <Routes>
              <Route path={path} element={ui} />
            </Routes>
          </ToastProvider>
        </AuthProvider>
      </I18nProvider>
    </MemoryRouter>,
  )
}
