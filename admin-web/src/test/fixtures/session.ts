/**
 * session.ts — the signed-in staff member that tests and the mock API assume.
 *
 * Shared by src/test/render.tsx, which seeds it into localStorage before a
 * render, and scripts/mock-api.mjs, which prints it at start-up so it can be
 * pasted into the browser console to skip the login screen. It is plain data
 * with a type-only import, so Node loads it with --experimental-strip-types.
 *
 * WHY super_admin
 * It is the tier every client-side gate lets through (isSuperAdmin,
 * canExportData, the tier fallback in lib/permissions.ts). A page therefore
 * renders all of its controls, and a test that is about restricted access
 * opts OUT by passing another user, instead of every test opting in.
 */
import type { StoredUser } from '../../lib/api'

/** The bearer token. The mock API never checks it; the app only needs one to exist. */
export const MOCK_TOKEN = 'mock'

/** A super_admin staff account, in the shape lib/api.ts keeps in localStorage. */
export const MOCK_STAFF_USER: StoredUser = {
  user_id: 1,
  phone: '+9647700000001',
  role_id: null,
  is_admin: 1,
  staff_tier: 'super_admin',
}

/**
 * The localStorage keys the app reads a session and locale from:
 * TOKEN_KEY and USER_KEY in lib/api.ts, and currentLocale() in lib/i18n.tsx.
 * Neither module exports them, so scripts/mock-api.test.mjs checks that these
 * strings still appear in those two files.
 */
export const SESSION_STORAGE_KEYS = {
  token: 'humanitarian.admin.token',
  user: 'humanitarian.admin.user',
  locale: 'locale',
} as const
