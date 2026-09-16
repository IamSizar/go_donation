// staffAccounts.ts — the one definition of "this account is staff".
//
// It used to live in UsersPage.tsx, but a file that exports a component may
// not also export plain functions: Vite's fast refresh can only swap a module
// whose exports are all components, so mixing the two silently downgrades
// every edit of that page to a full reload (react-refresh/only-export-
// components). The helper is shared between UsersPage (which excludes staff
// rows) and StaffPage (which shows only staff rows), so it belongs here.

import type { UserAccount } from './api-types'

// A row counts as "staff" the same way A15 defines it everywhere else:
// staff_tier set to anything other than the default 'user'. Shared so
// UsersPage and StaffPage can never drift on the definition.
export function isStaffAccount(u: UserAccount): boolean {
  return !!u.staff_tier && u.staff_tier !== 'user'
}
