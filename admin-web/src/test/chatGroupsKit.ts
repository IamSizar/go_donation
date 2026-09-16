/**
 * chatGroupsKit.ts — shared arrangements for the chat-group screen tests.
 *
 * WHAT IT CONTAINS
 * - The permission set-ups those tests need: a matrix with named actions
 *   switched off, and an `employee` session, whose tier fallback in
 *   lib/permissions.ts is "no". A test about a missing permission therefore
 *   cannot pass just because the matrix had not loaded yet.
 * - A users search reply built from the shared ADMIN_USERS fixture, answering
 *   UserPicker's GET /api/admin/users?q= the way the real endpoint does.
 * - The steps an operator takes on a member row (pick a person, choose a
 *   role, find the label box), so each test reads as what the operator does.
 *
 * HOW IT FITS
 * Used by ChatGroupsPage.test.tsx, CreateGroupDialog.test.tsx and
 * MemberRowsEditor.test.tsx. It lives under src/test/, which tsconfig.app.json
 * excludes, so nothing here ships in the app bundle.
 */
import { screen, within } from '@testing-library/react'
import type { UserEvent } from '@testing-library/user-event'
import type { StoredUser } from '../lib/api'
import type { MockApi } from './mockApi'
import { superAdminMatrix, type PermissionMatrix } from './fixtures/permissions'
import { MOCK_STAFF_USER } from './fixtures/session'
import { ADMIN_USERS } from './fixtures/shell'

// ─── Permissions ───

/** The route lib/permissions.ts reads the effective matrix from. */
export const PERMISSIONS_URL = '/api/admin/permissions/me'

/** The users search UserPicker calls. */
export const USERS_URL = '/api/admin/users'

/** A signed-in `employee`: the tier fallback denies every gated action. */
export const EMPLOYEE_USER: StoredUser = { ...MOCK_STAFF_USER, user_id: 7, staff_tier: 'employee' }

/**
 * A super_admin matrix with some actions changed.
 *
 * @param overrides  module → action → allowed, e.g. `{ users: { view: false } }`.
 * @returns          a fresh matrix every call.
 */
export function matrixWith(overrides: Record<string, Record<string, boolean>>): PermissionMatrix {
  const matrix = superAdminMatrix()
  for (const [module, actions] of Object.entries(overrides)) {
    matrix[module] = { ...matrix[module], ...actions }
  }
  return matrix
}

/**
 * Registers the permission matrix reply.
 *
 * @param api     the test's mock API.
 * @param matrix  the matrix to serve; every action allowed by default.
 * @returns       the same mock API, for chaining.
 */
export function servePermissions(api: MockApi, matrix: PermissionMatrix = superAdminMatrix()): MockApi {
  return api.on('get', PERMISSIONS_URL, { data: { success: true, tier: 'employee', permissions: matrix } })
}

/**
 * Registers the users search: `q` matched against full names, ignoring case,
 * in the `{ status, data, pagination }` envelope handlers/extras.go sends.
 *
 * @returns the same mock API, for chaining.
 */
export function serveUserSearch(api: MockApi): MockApi {
  return api.on('get', USERS_URL, (call) => {
    const q = String((call.params as { q?: string } | undefined)?.q ?? '').toLowerCase()
    const data = ADMIN_USERS.filter((u) => (u.profile?.full_name ?? '').toLowerCase().includes(q))
    return { data: { status: 'success', data, pagination: { page: 1, total_items: data.length } } }
  })
}

// ─── Member rows ───

/** The n-th member row (1-based), found by its "Member n" group name. */
export function memberRow(n: number): HTMLElement {
  return screen.getByRole('group', { name: `Member ${n}` })
}

/**
 * Picks a person on the n-th row: types their name into the search box and
 * chooses them from the results, as an operator would.
 */
export async function pickPerson(user: UserEvent, n: number, fullName: string): Promise<void> {
  const row = memberRow(n)
  await user.type(within(row).getByPlaceholderText('Search by name or phone…'), fullName)
  // UserPicker waits 300 ms after the last keystroke before it searches, on
  // real timers, so the default 1 s find can run out on a busy machine.
  const option = await within(row).findByRole('option', { name: new RegExp(fullName) }, { timeout: PICK_TIMEOUT_MS })
  await user.click(option)
}

/** How long pickPerson waits for the search result to appear. */
const PICK_TIMEOUT_MS = 4000

/** Chooses a role, by its machine value, on the n-th row. */
export async function chooseRole(user: UserEvent, n: number, role: string): Promise<void> {
  await user.selectOptions(within(memberRow(n)).getByRole('combobox', { name: 'Role in the group' }), role)
}

/** The masked-label text box on the n-th row. */
export function labelBox(n: number): HTMLElement {
  return within(memberRow(n)).getByRole('textbox', { name: 'Label shown to other members' })
}
