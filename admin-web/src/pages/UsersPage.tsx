import { useCallback, useEffect, useMemo, useState } from 'react'
import ActionsMenu from '../components/ActionsMenu'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError, isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { roleLabel, type UsersListResp, type UserAccount } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import StatusCell from '../components/StatusCell'
import EditModal, { type FieldSpec } from '../components/EditModal'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'
import { type CsvColumn } from '../lib/csv'
import { formatPhone } from '../lib/phone'
import { useCanViewSensitive, usePermission, maskContact } from '../lib/permissions'
import { useFieldRules, type FieldRuleState } from '../lib/fieldRules'

const PER_PAGE = 20

const ROLE_LABELS = ['donor', 'beneficiary', 'volunteer', 'employee', 'none']
const GENDER_OPTIONS = ['', 'Male', 'Female', 'Other']

// Phase 18: editable fields. role / active / is_admin live in their own
// dedicated /status endpoints (Phase 9 inline dropdowns), so they're omitted
// from this form to avoid two ways to set the same column.
//
// Note #6 — this used to be only 5 of the 16 columns user_profiles actually
// has; the other 8 (collected at registration) were only ever viewable
// read-only on the Detail page, never editable. Extended to the full set,
// plus a password field (routed to the separate password endpoint in
// handleUserSave below — the backend keeps password changes on their own
// endpoint, this just gives it a home in the same form instead of a
// separate popup prompt).
const USER_FIELDS: FieldSpec[] = [
  { key: 'phone',           label: 'Phone', labelKey: 'field.phone',           type: 'text', required: true },
  { key: 'full_name',       label: 'Full name', labelKey: 'field.full_name',       type: 'text' },
  { key: 'gender',          label: 'Gender', labelKey: 'field.gender',          type: 'select', options: GENDER_OPTIONS },
  { key: 'date_of_birth',   label: 'Date of birth', labelKey: 'field.date_of_birth', type: 'date' },
  { key: 'address',         label: 'Address', labelKey: 'field.address',         type: 'textarea', rows: 2 },
  { key: 'city',            label: 'City', labelKey: 'field.city',            type: 'text' },
  { key: 'occupation',      label: 'Occupation', labelKey: 'field.occupation',      type: 'text' },
  { key: 'housing_status',  label: 'Housing status', labelKey: 'field.housing_status',  type: 'text' },
  { key: 'family_size',     label: 'Family size', labelKey: 'field.family_size',     type: 'number' },
  { key: 'monthly_income',  label: 'Monthly income', labelKey: 'field.monthly_income',  type: 'text' },
  { key: 'availability',    label: 'Availability', labelKey: 'field.availability',    type: 'text' },
  { key: 'experience',      label: 'Experience', labelKey: 'field.experience',      type: 'text' },
  { key: 'skills',          label: 'Skills', labelKey: 'field.skills',          type: 'textarea', rows: 2, full: true },
  { key: 'profile_picture', label: 'Profile picture', labelKey: 'field.profile_picture', type: 'file', full: true },
  { key: 'password',        label: 'New password', labelKey: 'field.new_password',    type: 'password', placeholder: 'Leave blank to keep unchanged', full: true },
]

// Note #34 — the New-User form used to only have phone/full_name/role; the
// rest of user_profiles (already collected by the Edit form above) is now
// available here too, gated per-field by Field Rules under a "user_" prefix
// (migration 057) — same mechanism as buildCaseFields/buildMarriageFields,
// kept independent from the public sign-up form's own rules since this is a
// separate, admin-only data-entry screen. phone/role stay fixed: phone is
// the required login identifier, role is an admin classification choice,
// neither is applicant data collected about the person.
function buildNewUserFields(state: Record<string, FieldRuleState>): FieldSpec[] {
  const isRequired = (key: string) => state[key] === 'required'
  const isHidden = (key: string) => state[key] === 'hidden'
  const fields: FieldSpec[] = [
    { key: 'phone',           label: 'Phone', labelKey: 'field.phone',           type: 'text', required: true },
    { key: 'role',            label: 'Role', labelKey: 'col.role',              type: 'select', options: ['donor', 'beneficiary', 'volunteer', 'employee'] },
    { key: 'full_name',       label: 'Full name', labelKey: 'field.full_name',       type: 'text', required: isRequired('full_name') },
    { key: 'gender',          label: 'Gender', labelKey: 'field.gender',          type: 'select', options: GENDER_OPTIONS, required: isRequired('gender') },
    { key: 'date_of_birth',   label: 'Date of birth', labelKey: 'field.date_of_birth', type: 'date', required: isRequired('date_of_birth') },
    { key: 'address',         label: 'Address', labelKey: 'field.address',         type: 'textarea', rows: 2, required: isRequired('address') },
    { key: 'city',            label: 'City', labelKey: 'field.city',            type: 'text', required: isRequired('city') },
    { key: 'occupation',      label: 'Occupation', labelKey: 'field.occupation',      type: 'text', required: isRequired('occupation') },
    { key: 'housing_status',  label: 'Housing status', labelKey: 'field.housing_status',  type: 'text', required: isRequired('housing_status') },
    { key: 'family_size',     label: 'Family size', labelKey: 'field.family_size',     type: 'number', required: isRequired('family_size') },
    { key: 'monthly_income',  label: 'Monthly income', labelKey: 'field.monthly_income',  type: 'text', required: isRequired('monthly_income') },
    { key: 'availability',    label: 'Availability', labelKey: 'field.availability',    type: 'text', required: isRequired('availability') },
    { key: 'experience',      label: 'Experience', labelKey: 'field.experience',      type: 'text', required: isRequired('experience') },
    { key: 'skills',          label: 'Skills', labelKey: 'field.skills',          type: 'textarea', rows: 2, full: true, required: isRequired('skills') },
    { key: 'profile_picture', label: 'Profile picture', labelKey: 'field.profile_picture', type: 'file', full: true, required: isRequired('profile_picture') },
  ]
  return fields.filter((f) => f.key === 'phone' || f.key === 'role' || !isHidden(f.key))
}

const USER_CSV_COLUMNS: CsvColumn<UserAccount>[] = [
  { header: 'user_id', get: (u) => u.user_id },
  { header: 'phone', get: (u) => u.phone },
  { header: 'full_name', get: (u) => u.profile?.full_name },
  { header: 'role_id', get: (u) => u.role_id },
  { header: 'role', get: (u) => roleLabel(u.role_id) },
  { header: 'active', get: (u) => u.active },
  { header: 'is_admin', get: (u) => u.is_admin },
  { header: 'created_at', get: (u) => u.created_at },
]

function roleLabelToId(label: string): number {
  if (label === 'donor') return 1
  if (label === 'beneficiary') return 2
  if (label === 'volunteer') return 3
  if (label === 'employee') return 4
  return 0
}

// Flatten the {users + nested profile} shape into the flat key/value object
// the EditModal expects. Strips the nested `profile` so its keys can be
// addressed directly by name.
function flattenForEdit(u: UserAccount): Record<string, unknown> {
  return {
    phone:           u.phone,
    full_name:       u.profile?.full_name ?? '',
    gender:          u.profile?.gender ?? '',
    date_of_birth:   u.profile?.date_of_birth ?? '',
    address:         u.profile?.address ?? '',
    city:            u.profile?.city ?? '',
    occupation:      u.profile?.occupation ?? '',
    housing_status:  u.profile?.housing_status ?? '',
    family_size:     u.profile?.family_size != null ? String(u.profile.family_size) : '',
    monthly_income:  u.profile?.monthly_income ?? '',
    availability:    u.profile?.availability ?? '',
    experience:      u.profile?.experience ?? '',
    skills:          u.profile?.skills ?? '',
    profile_picture: u.profile?.profile_picture ?? '',
    // password is intentionally never pre-filled — blank means "unchanged".
    password: '',
  }
}

export default function UsersPage() {
  const [page, setPage] = useState(1)
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<UsersListResp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<UserAccount | null>(null)
  const [deleting, setDeleting] = useState<UserAccount | null>(null)
  const [creating, setCreating] = useState(false)
  const [refreshTick, setRefreshTick] = useState(0)
  const toast = useToast()
  const { t } = useI18n()
  const { user: authUser } = useAuth()
  const amSuper = isSuperAdmin(authUser)
  const canViewSensitive = useCanViewSensitive(authUser)
  const { state: newUserFieldState } = useFieldRules('user_')
  const newUserFields = useMemo(() => buildNewUserFields(newUserFieldState), [newUserFieldState])
  // Note #4 — Archive is the reversible, non-destructive alternative to
  // Delete; a Super Admin decides per-tier (Permissions page) who besides
  // admins gets it. Delete itself stays hard-restricted to amSuper below —
  // deliberately NOT permission-configurable, per the client's explicit ask.
  const canArchive = usePermission('users', 'archive', authUser)

  // PIN step-up used before sensitive user changes (role/tier/delete).
  const verifyPin = async () => {
    const pin = window.prompt(t('export.pin_prompt'))
    if (pin == null || !pin.trim()) throw new Error(t('export.pin_required'))
    const { data } = await api.post('/api/admin/verify-password', { password: pin })
    if (!data?.ok) throw new Error(data?.error || t('export.pin_incorrect'))
  }

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setErr(null)
    api
      .get<UsersListResp>('/api/admin/users', { params: { page, per_page: PER_PAGE, q: q || undefined } })
      .then((res) => {
        if (!cancelled) setResp(res.data)
      })
      .catch((e) => {
        if (!cancelled) setErr(describeError(e))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [page, q, refreshTick])

  // Note #6 — the Edit form now includes a password field, but the backend
  // keeps password changes on its own endpoint (POST .../password) rather
  // than the profile PATCH. Split it out here so the form can look like one
  // unified "Edit User" screen while the two writes stay separate underneath.
  // If only the password changed, the profile PATCH is skipped entirely —
  // the backend rejects an empty patch with "No fields to update".
  // Investigation finding — the mobile app's phone/OTP login has NO password
  // input anywhere in its UI (checked login.dart directly; the only
  // password-handling file, auth_controller.dart, is dead scaffold code with
  // a literal 'YOUR_LOGIN_API_URL_HERE' placeholder, never wired up). But
  // the backend's phone-login endpoint DOES require a password on every
  // future login once one is set on that account (Phase 20 "password gate",
  // auth.go). So setting a password on a regular app user (not staff/admin)
  // doesn't just do nothing — it silently locks them out of their normal
  // login with no way back in through the app. Warn before it happens;
  // staff/admin accounts (is_admin=1) are exactly what this field is for and
  // skip the warning.
  const confirmPasswordSet = useCallback(
    (u: UserAccount) => {
      if (u.is_admin === 1) return true
      return window.confirm(t('page.users.password_non_staff_warning'))
    },
    [t],
  )

  const handleSave = useCallback(
    async (u: UserAccount, patch: Record<string, unknown>) => {
      const { password, ...profilePatch } = patch
      const settingPassword = typeof password === 'string' && password.trim() !== ''
      if (settingPassword && !confirmPasswordSet(u)) {
        throw new Error(t('page.users.password_cancelled'))
      }
      await verifyPin() // Note #9 — PIN before saving any account edit.
      if (Object.keys(profilePatch).length > 0) {
        await api.patch(`/api/admin/users/${u.user_id}`, profilePatch)
      }
      if (settingPassword) {
        await api.post(`/api/admin/users/${u.user_id}/password`, { password: (password as string).trim() })
      }
      toast.success(t('toast.saved', { noun: `${t('noun.user')} #${u.user_id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast, t, confirmPasswordSet],
  )

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/users/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.user')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  // Note #4 — Delete now needs the password step-up BEFORE the "are you
  // sure?" dialog even opens; the dialog alone was the entire protection
  // before (no password, and the button was visible to every tier with no
  // permission check at all).
  const requestDelete = useCallback(
    async (u: UserAccount) => {
      try {
        await verifyPin()
        setDeleting(u)
      } catch (e) {
        toast.error(describeError(e))
      }
    },
    [toast],
  )

  const handleArchiveToggle = useCallback(
    async (u: UserAccount) => {
      const archiving = u.account_status !== 'archived'
      try {
        await verifyPin() // Note #9 — PIN before archive/unarchive.
        await api.post(`/api/admin/users/${u.user_id}/archive`, { archived: archiving })
        toast.success(
          archiving
            ? t('page.users.archived_ok', { noun: `${t('noun.user')} #${u.user_id}` })
            : t('page.users.unarchived_ok', { noun: `${t('noun.user')} #${u.user_id}` }),
        )
        setRefreshTick((t) => t + 1)
      } catch (e) {
        toast.error(describeError(e))
      }
    },
    [toast, t],
  )


  const columns: Column<UserAccount>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (u) => <strong>#{u.user_id}</strong> },
    {
      key: 'name',
      header: t('col.name'),
      // Note #40 — guests have no user_profiles row, so fall back to their
      // username with a "Guest" badge so they read as distinct from a
      // normal account with a missing name.
      cell: (u) =>
        u.profile?.full_name ?? (u.is_guest ? (
          <span>
            {u.username ?? <span className="muted">—</span>}{' '}
            <span className="badge" style={{ opacity: 0.75 }}>{t('page.users.guest_badge')}</span>
          </span>
        ) : (
          <span className="muted">—</span>
        )),
    },
    { key: 'phone', header: t('col.phone'), cell: (u) => canViewSensitive ? formatPhone(u.phone) : maskContact(u.phone, false) },
    {
      // Note #10 — labeled "User Type" now (was "Role"), to stop it reading
      // as a duplicate of the "Access Permission" column below. This is the
      // APP-side classification (donor/beneficiary/volunteer/employee) used
      // by beneficiary gating, volunteer broadcasts, and dashboard stats —
      // a different concept from staff_tier's dashboard permission level,
      // even though "Employee" appears in both option lists.
      key: 'role',
      header: t('col.role'),
      cell: (u) => (
        <StatusCell
          value={roleLabel(u.role_id)}
          allowed={ROLE_LABELS}
          onSave={async (next) => {
            await verifyPin() // Global notice #b — PIN before a role change.
            await api.post(`/api/admin/users/${u.user_id}/role`, { role_id: roleLabelToId(next) })
          }}
          label={`User #${u.user_id} role`}
        />
      ),
    },
    {
      // Note #10 — was 3 separate columns (Admin, Access tier, and this one)
      // showing overlapping Admin/User/Supervisor wording. `is_admin` never
      // gated anything independently of `staff_tier` (a 2023 migration folded
      // every is_admin=1 account into staff_tier='admin'), so the standalone
      // "Admin" column was pure duplication — dropped. This is now the single
      // "Access Permission" column. Only the Super-Admin can change it; others
      // see it read-only. PIN-confirmed.
      key: 'tier',
      header: t('col.tier'),
      cell: (u) => (
        <StatusCell
          value={u.staff_tier ?? 'user'}
          allowed={['super_admin', 'admin', 'supervisor', 'employee', 'user']}
          disabled={!amSuper}
          onSave={async (next) => {
            await verifyPin()
            await api.post(`/api/admin/users/${u.user_id}/staff_tier`, { staff_tier: next })
          }}
          label={`User #${u.user_id} tier`}
        />
      ),
    },
    {
      // Note #10 — the old standalone "Active" (Yes/No) column is gone.
      // `account_status` is the field the auth layer actually enforces on
      // every request; `active` was only ever a weak, one-shot side effect
      // (checked — never read at login). The account_status endpoint already
      // syncs `active` in the same UPDATE (admin_status.go UserAccountStatus),
      // so merging costs nothing: active/suspended/banned covers the same
      // ground as active/suspended/banned+Active/Inactive did, minus the
      // duplicate control. "banned" displays as "Blocked" per the client's
      // wording; the stored value is unchanged. Super-Admin only,
      // PIN-confirmed. Suspending or banning force-logs-out every session.
      key: 'account_status',
      header: t('col.account_status'),
      cell: (u) => (
        <StatusCell
          value={u.account_status ?? 'active'}
          allowed={['active', 'suspended', 'banned']}
          disabled={!amSuper}
          onSave={async (next) => {
            await verifyPin()
            await api.post(`/api/admin/users/${u.user_id}/account_status`, { status: next })
          }}
          label={t('col.account_status')}
        />
      ),
    },
    {
      key: 'created',
      header: t('col.created'),
      cell: (u) => <span className="muted">{u.created_at?.slice(0, 10)}</span>,
    },
    {
      // Note #4 — was 5 loose inline buttons (View/Edit/Password/Force
      // logout/Delete) that wrapped and cluttered the row. Now one "Actions"
      // menu. Delete is hard-restricted to amSuper (Super Admin / Primary
      // Administrator) with a password step-up before the confirm dialog
      // even opens (requestDelete); Archive is the reversible alternative
      // available to whichever tier has been granted the "archive"
      // permission (defaults to Supervisor+, configurable on Permissions).
      key: 'actions', header: t('common.actions'), width: '110px',
      cell: (u) => {
        const archived = u.account_status === 'archived'
        return (
          <ActionsMenu
            items={[
              { key: 'view', label: t('common.view'), href: `/detail/users/${u.user_id}`, onClick: () => {} },
              { key: 'edit', label: t('common.edit'), onClick: () => setEditing(u) },
              {
                key: 'password',
                label: t('common.set_password'),
                onClick: async () => {
                  if (!confirmPasswordSet(u)) return
                  const pw = window.prompt(t('common.set_password_prompt'))
                  if (pw === null) return
                  try {
                    await verifyPin() // Note #9 — PIN before setting a password.
                    await api.post(`/api/admin/users/${u.user_id}/password`, { password: pw })
                    toast.success(t('common.set_password_ok'))
                  } catch (e) {
                    toast.error(describeError(e))
                  }
                },
              },
              ...(canArchive
                ? [
                    {
                      key: 'archive',
                      label: archived ? t('page.users.unarchive') : t('page.users.archive'),
                      onClick: () => handleArchiveToggle(u),
                    },
                  ]
                : []),
              // Force Logout — Super-Admin only; revokes every session for
              // the user across mobile + browser (Section 25).
              ...(amSuper
                ? [
                    {
                      key: 'force_logout',
                      label: t('page.users.force_logout'),
                      onClick: async () => {
                        try {
                          await verifyPin() // Note #9 — PIN before force logout.
                          await api.post(`/api/admin/users/${u.user_id}/force_logout`)
                          toast.success(t('page.users.force_logout_ok'))
                        } catch (e) {
                          toast.error(describeError(e))
                        }
                      },
                    },
                  ]
                : []),
              // Delete — Super-Admin only (both here and enforced server-side
              // via RequireSuperAdmin, not the overridable permission flag),
              // password-confirmed via requestDelete before the "are you
              // sure?" dialog opens.
              ...(amSuper
                ? [
                    {
                      key: 'delete',
                      label: t('common.delete'),
                      danger: true,
                      onClick: () => requestDelete(u),
                    },
                  ]
                : []),
            ]}
          />
        )
      },
    },
  ]

  const handleCreate = async (patch: Record<string, unknown>) => {
    const phone = String(patch.phone ?? '').trim()
    const roleSel = String(patch.role ?? '')
    // Note #34 — everything besides phone/role passes through as-is; EditModal
    // already omits untouched optional fields and converts family_size to a
    // number, matching what POST /api/admin/users now accepts.
    const { phone: _phone, role: _role, ...profileFields } = patch
    try {
      await api.post('/api/admin/users', {
        phone,
        full_name: String(patch.full_name ?? ''),
        role_id: roleSel ? roleLabelToId(roleSel) : undefined,
        ...profileFields,
      })
      toast.success(t('toast.created', { noun: t('noun.user') }))
      setCreating(false)
      setRefreshTick((n) => n + 1)
    } catch (e) {
      toast.error(describeError(e))
      throw e
    }
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.users.title')}</h1>
          <p className="muted">
            {resp ? `${resp.pagination.total_items} ${t('common.total')}` : t('common.loading')}
          </p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1) }}
            placeholder={t('page.users.search_placeholder')}
            style={{ width: '220px' }}
          />
          <button className="primary" onClick={() => setCreating(true)}>
            {t('page.users.new_user')}
          </button>
          <ExportCsvButton
            rows={resp?.data ?? []}
            columns={USER_CSV_COLUMNS}
            filenameBase="users"
            title={t('nav.users')}
            module="users"
          />
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<UserAccount>
        rows={resp?.data ?? []}
        columns={columns}
        rowKey={(u) => u.user_id}
        loading={loading}
        empty={t('empty.users')}
      />
      <Pagination
        page={page}
        totalPages={resp?.pagination.total_pages ?? 1}
        onPageChange={setPage}
        disabled={loading}
      />
      <EditModal
        open={editing !== null}
        title={editing ? t('common.modal_edit', { noun: t('noun.user'), id: editing.user_id }) : ''}
        initial={editing ? flattenForEdit(editing) : {}}
        fields={USER_FIELDS}
        onSave={(patch) => handleSave(editing!, patch)}
        onClose={() => setEditing(null)}
      />
      <EditModal
        open={creating}
        title={t('page.users.new_user')}
        initial={{}}
        fields={newUserFields}
        onSave={handleCreate}
        onClose={() => setCreating(false)}
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.user'), id: deleting.user_id }) : ''}
        message={deleting ? t('page.users.delete_body', { name: deleting.profile?.full_name ?? deleting.phone }) : ''}
        onConfirm={() => handleDelete(deleting!.user_id)}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}
