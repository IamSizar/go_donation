/**
 * permissions.ts — the permission matrix the mock API serves.
 *
 * GET /api/admin/permissions/me answers
 *   { success, tier, permissions: { <module>: { <action>: boolean } } }
 * (backend/internal/handlers/admin_permissions.go, Effective). AppShell hides
 * a sidebar entry whose `view` is false, and lib/permissions.ts gates exports
 * and actions on the rest.
 *
 * The two lists mirror permissions.Modules and permissions.AllActions in
 * backend/internal/permissions/permissions.go. scripts/mock-api.test.mjs reads
 * that file and fails if either list drifts from it. Plain data, so Node can
 * load this file with --experimental-strip-types.
 */

/** Every module slug the backend matrix contains, in the backend's order. */
export const PERMISSION_MODULES = [
  'dashboard', 'registrations', 'users', 'campaigns', 'donations',
  'sponsorships', 'beneficiary', 'marketplace', 'in_kind', 'partners',
  'media', 'community', 'city', 'marriage', 'missions', 'volunteers', 'tasks',
  'messages', 'notifications', 'push', 'reports', 'audit', 'support', 'trash',
  'sensitive_data',
] as const

/** Every action the matrix exposes for each module, in the backend's order. */
export const PERMISSION_ACTIONS = ['view', 'add', 'edit', 'archive', 'delete', 'export'] as const

/** A permission matrix: module slug → action → allowed. */
export type PermissionMatrix = Record<string, Record<string, boolean>>

/**
 * The matrix of a super_admin: every action allowed on every module, so no
 * sidebar entry, button or export is hidden during a browser check.
 *
 * @returns a new object on every call, so a caller can change its copy freely.
 */
export function superAdminMatrix(): PermissionMatrix {
  const allowAll = (): Record<string, boolean> =>
    Object.fromEntries(PERMISSION_ACTIONS.map((action) => [action, true]))
  return Object.fromEntries(PERMISSION_MODULES.map((module) => [module, allowAll()]))
}
