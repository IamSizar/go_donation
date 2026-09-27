import UsersPage from './UsersPage'

// المانحون — donor accounts (role 1). Same list, edit form and actions as the
// Users page, narrowed server-side with ?role_id=1 so pages stay full and the
// total counts donors only.
export default function DonorsPage() {
  return <UsersPage roleId={1} />
}
