// usersListParams — which accounts each list shows (client #81: "full
// separation of account lists"). One pure function, so the rule is tested and
// every list asks the server the same way.
//
// Separation rules (the server enforces them too — see PaginatedListByRole):
//   • staff accounts never appear in an account list (staff=0); they live on
//     the Staff page only;
//   • a list scoped to a role (donors, beneficiaries, volunteers, family files)
//     never contains one-tap guests — guests are their own list;
//   • the guests list contains guests only, whatever their role.
// No new role is introduced: these are the existing role ids + is_guest.

export type UsersKind = '' | 'donor' | 'beneficiary' | 'volunteer' | 'employee' | 'marriage' | 'general' | 'guest'

/** role id of each kind (guest has none: it is is_guest, not a role). */
export const KIND_ROLE_ID: Record<Exclude<UsersKind, '' | 'guest'>, number> = {
  donor: 1,
  beneficiary: 2,
  volunteer: 3,
  employee: 4,
  marriage: 5,
  general: 6,
}

export type UsersListInput = {
  page: number
  perPage: number
  q: string
  status: string
  hideGuests: boolean
  /** A page fixed to one role (the Donors page). */
  roleId?: number
  /** The in-page "type" filter on the general list. */
  kind: UsersKind
}

export function usersListParams(i: UsersListInput): Record<string, string | number | undefined> {
  const guestsOnly = i.kind === 'guest'
  const roleId = guestsOnly ? undefined : (i.roleId ?? (i.kind && i.kind !== 'guest' ? KIND_ROLE_ID[i.kind] : undefined))
  return {
    page: i.page,
    per_page: i.perPage,
    q: i.q || undefined,
    status: i.status || undefined,
    staff: 0,
    guests: guestsOnly ? 1 : undefined,
    // A role-scoped list never carries guests; the guests list needs them.
    hide_guests: !guestsOnly && (i.hideGuests || roleId !== undefined) ? 1 : undefined,
    role_id: roleId,
  }
}
