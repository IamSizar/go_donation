// StaffPage — System Settings · Staff (owner ask: "move staff to system
// settings out from users").
//
// Staff accounts (staff_tier set to anything but the default 'user') used to
// be mixed into the Users list — same table, same rows, only distinguished by
// an "Access Permission" column. UsersPage.tsx now filters them out entirely
// (see isStaffAccount/A15 there); this page is their new, dedicated home.
//
// Every gate this page exercises is the SAME endpoint + SAME client wrapper
// UsersPage used before the move — verifyPin (PIN step-up), withMainAdmin-
// Confirmation (H20 two-channel confirmation on the Primary Administrator's
// own row), and askForText's in-app dialog (the prompt()-free fallback,
// commit 518f850) for the PIN/OTP/password prompts. Nothing about what a role
// is ALLOWED to do changed — only where the controls that do it live.
import { useCallback, useEffect, useMemo, useState } from 'react'
import ActionsMenu from '../components/ActionsMenu'
import { api, describeError, isSuperAdmin, withMainAdminConfirmation } from '../lib/api'
import { askForText } from '../lib/dialogs'
import { useAuth } from '../lib/auth'
import type { UsersListResp, UserAccount } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import StatusCell from '../components/StatusCell'
import EditModal from '../components/EditModal'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { formatPhone } from '../lib/phone'
import { usePermission } from '../lib/permissions'
import PageHead from '../components/PageHead'
import { fmtId } from '../lib/formatId'
import { formatDateTime } from '../lib/dates'
import { isStaffAccount } from './UsersPage'
import { USER_FIELDS, flattenForEdit } from '../lib/userEditFields'
import { useUserEditProfile } from '../lib/useUserEditProfile'

// Every tier the "Access Permission" column offered on Users before the move
// — unchanged, including 'super_admin' being a selectable target. This is a
// relocation, not a permissions change, so the allowed set stays identical
// wherever it appears below (the per-row tier cell AND the promote form).
const STAFF_TIERS = ['super_admin', 'admin', 'supervisor', 'employee']
const TIER_CELL_OPTIONS = [...STAFF_TIERS, 'user']

// A large-but-bounded fetch instead of real pagination: staff accounts are a
// small slice of all users (per_employee picker on PermissionsPage.tsx makes
// the same per_page:200 assumption for the same reason), and the backend has
// no staff/non-staff query param to filter server-side.
const FETCH_PER_PAGE = 200

export default function StaffPage() {
  const [q, setQ] = useState('')
  const [statusView, setStatusView] = useState('')
  const [resp, setResp] = useState<UsersListResp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<UserAccount | null>(null)
  // Same modal as the Users page, so the same on-demand profile load — see
  // lib/useUserEditProfile.ts. Sharing the hook is what keeps the two screens
  // from drifting apart again.
  const {
    profile: editProfile,
    loading: editLoading,
    error: editError,
    reload: reloadEditProfile,
  } = useUserEditProfile(editing?.user_id ?? null)
  const [deleting, setDeleting] = useState<UserAccount | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  const toast = useToast()
  const { t } = useI18n()
  // Same label source StatusCell uses internally for the tier cell below
  // (status.*) — reused here so the promote form's tier <select> shows the
  // identical word for the identical value, including 'super_admin', which
  // perm.tier.* (PermissionsPage's separate namespace, scoped to the
  // permissions matrix's configurable tiers) does not cover.
  const statusLabel = useStatusLabel()
  const { user: authUser } = useAuth()
  const amSuper = isSuperAdmin(authUser)
  const canArchive = usePermission('users', 'archive', authUser)

  // ── Promote-to-staff form state ──────────────────────────────────────
  const [promotePhone, setPromotePhone] = useState('')
  const [promoteTier, setPromoteTier] = useState('employee')
  const [promoting, setPromoting] = useState(false)

  // PIN step-up — identical to UsersPage's verifyPin (H1's in-app dialog
  // fallback for browsers that refuse window.prompt(), commit 518f850).
  const verifyPin = async () => {
    const pin = await askForText({
      title: t('auth.password'),
      message: t('export.pin_prompt'),
      secret: true,
    })
    if (pin == null || !pin.trim()) throw new Error(t('export.pin_required'))
    const { data } = await api.post('/api/admin/verify-password', { password: pin })
    if (!data?.ok) throw new Error(data?.error || t('export.pin_incorrect'))
  }

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setErr(null)
    api
      .get<UsersListResp>('/api/admin/users', {
        params: { page: 1, per_page: FETCH_PER_PAGE, q: q || undefined, status: statusView || undefined },
      })
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
  }, [q, statusView, refreshTick])

  const staffRows = useMemo(() => (resp?.data ?? []).filter(isStaffAccount), [resp])

  const handleSave = useCallback(
    async (u: UserAccount, patch: Record<string, unknown>) => {
      const { password, ...profilePatch } = patch
      const settingPassword = typeof password === 'string' && password.trim() !== ''
      // Note #9's bootstrap exception, unchanged: no existing password_hash
      // means verify-password would 403 forever, so skip the PIN only for a
      // FIRST password on an account that has none yet.
      if (!(settingPassword && !u.has_password)) {
        await verifyPin()
      }
      if (Object.keys(profilePatch).length > 0) {
        await withMainAdminConfirmation((extra) =>
          api.patch(`/api/admin/users/${u.user_id}`, { ...profilePatch, ...extra }),
        )
      }
      if (settingPassword) {
        await withMainAdminConfirmation((extra) =>
          api.post(`/api/admin/users/${u.user_id}/password`, {
            password: (password as string).trim(),
            ...extra,
          }),
        )
      }
      toast.success(t('toast.saved', { noun: `${t('noun.staff')} #${u.user_id}` }))
      setRefreshTick((n) => n + 1)
    },
    [toast, t],
  )

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/users/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.staff')} #${id}` }))
      setDeleting(null)
      setRefreshTick((n) => n + 1)
    },
    [toast, t],
  )

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
        await verifyPin()
        await api.post(`/api/admin/users/${u.user_id}/archive`, { archived: archiving })
        toast.success(
          archiving
            ? t('page.staff.archived_ok', { noun: `${t('noun.staff')} #${u.user_id}` })
            : t('page.staff.unarchived_ok', { noun: `${t('noun.staff')} #${u.user_id}` }),
        )
        setRefreshTick((n) => n + 1)
      } catch (e) {
        toast.error(describeError(e))
      }
    },
    [toast, t],
  )

  // Promote an existing, currently non-staff account into staff. Same
  // endpoint + same PIN/H20 gates as the per-row tier cell below — this is
  // the one new action the move needed, since a fresh account has no staff
  // row to click a tier cell on yet.
  const handlePromote = useCallback(async () => {
    const phone = promotePhone.trim()
    if (!phone) return
    setPromoting(true)
    try {
      const { data } = await api.get<UsersListResp>('/api/admin/users', {
        params: { page: 1, per_page: 10, q: phone },
      })
      const match = (data.data ?? []).find((u) => u.phone === phone)
      if (!match) {
        toast.error(t('page.staff.promote_not_found'))
        return
      }
      if (isStaffAccount(match)) {
        toast.error(t('page.staff.promote_already_staff'))
        return
      }
      await verifyPin()
      await withMainAdminConfirmation((extra) =>
        api.post(`/api/admin/users/${match.user_id}/staff_tier`, { staff_tier: promoteTier, ...extra }),
      )
      toast.success(t('page.staff.promote_ok', { name: match.profile?.full_name ?? match.phone }))
      setPromotePhone('')
      setRefreshTick((n) => n + 1)
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setPromoting(false)
    }
  }, [promotePhone, promoteTier, toast, t])

  const columns: Column<UserAccount>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (u) => <strong>{fmtId(u.user_id)}</strong> },
    {
      key: 'name',
      header: t('col.name'),
      cell: (u) => u.profile?.full_name?.trim() || <span className="muted">—</span>,
    },
    // H10 — server-decided masking, unchanged from UsersPage: formatPhone
    // passes a redaction through untouched rather than the client hiding it.
    { key: 'phone', header: t('col.phone'), cell: (u) => formatPhone(u.phone) },
    {
      // The same "Access Permission" control UsersPage used to render, moved
      // here verbatim: same allowed set, same amSuper gate, same PIN + H20
      // wrapper. Demoting a row back to 'user' here is how a staff member
      // returns to being a plain user — the row then disappears from this
      // list and reappears on Users, symmetric with promotion below.
      key: 'tier',
      header: t('col.tier'),
      cell: (u) => (
        <StatusCell
          value={u.staff_tier ?? 'user'}
          allowed={TIER_CELL_OPTIONS}
          disabled={!amSuper}
          onSave={async (next) => {
            await verifyPin()
            // H20 — moving the Primary Administrator's own tier still needs
            // the two-channel confirmation; every other tier is unaffected.
            await withMainAdminConfirmation((extra) =>
              api.post(`/api/admin/users/${u.user_id}/staff_tier`, { staff_tier: next, ...extra }),
            )
            setRefreshTick((n) => n + 1)
          }}
          label={t('common.user_tier_ref', { id: u.user_id })}
        />
      ),
    },
    {
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
      cell: (u) => <span className="muted">{formatDateTime(u.created_at)}</span>,
    },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '110px',
      cell: (u) => {
        const archived = u.account_status === 'archived'
        return (
          <ActionsMenu
            items={[
              { key: 'view', label: t('common.view'), href: `/detail/users/${u.user_id}`, onClick: () => {} },
              // The employee profile: what this person has decided. Sits
              // beside "view" (which shows the RECORD) because the owner's ask
              // was about their work, not their row.
              {
                key: 'activity',
                label: t('staff_activity.open'),
                href: `/staff/${u.user_id}/activity`,
                onClick: () => {},
              },
              // Task 1 (owner ask: "password change button collapse into one
              // instead of 2") — removed the standalone "Set Password" action
              // that used to sit next to "Edit" here. It hit the identical
              // endpoint (POST .../password) with the identical PIN gate as
              // the Edit modal's "New password" field (USER_FIELDS, wired
              // through handleSave above) — same action, two buttons. The
              // Edit modal is now the only surface; handleSave's PIN/H20
              // sequence is unchanged.
              { key: 'edit', label: t('common.edit'), onClick: () => setEditing(u) },
              ...(canArchive
                ? [
                    {
                      key: 'archive',
                      label: archived ? t('page.users.unarchive') : t('page.users.archive'),
                      onClick: () => handleArchiveToggle(u),
                    },
                  ]
                : []),
              ...(amSuper
                ? [
                    {
                      key: 'force_logout',
                      label: t('page.users.force_logout'),
                      onClick: async () => {
                        try {
                          await verifyPin()
                          await api.post(`/api/admin/users/${u.user_id}/force_logout`)
                          toast.success(t('page.users.force_logout_ok'))
                        } catch (e) {
                          toast.error(describeError(e))
                        }
                      },
                    },
                  ]
                : []),
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

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('page.staff.title')}</h1>
          <p className="muted">{t('page.staff.subtitle')}</p>
        </div>
        <div className="row">
          <select
            value={statusView}
            onChange={(e) => setStatusView(e.target.value)}
            style={{ width: 'auto' }}
          >
            <option value="">{t('page.users.view_active')}</option>
            <option value="archived">{t('page.users.view_archived')}</option>
            <option value="all">{t('filter.all_statuses')}</option>
          </select>
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t('page.users.search_placeholder')}
            style={{ width: '220px' }}
          />
        </div>
      </PageHead>

      {amSuper && (
        <div className="card stack" style={{ gap: 12 }}>
          <div>
            <h3 style={{ margin: 0 }}>{t('page.staff.promote_title')}</h3>
            <p className="muted" style={{ marginTop: 4 }}>{t('page.staff.promote_desc')}</p>
          </div>
          <div className="row" style={{ flexWrap: 'wrap', gap: 8 }}>
            <input
              type="text"
              dir="ltr"
              inputMode="tel"
              value={promotePhone}
              onChange={(e) => setPromotePhone(e.target.value)}
              placeholder={t('page.staff.promote_phone_placeholder')}
              style={{ width: '220px' }}
              disabled={promoting}
            />
            <select
              value={promoteTier}
              onChange={(e) => setPromoteTier(e.target.value)}
              style={{ width: 'auto' }}
              disabled={promoting}
            >
              {STAFF_TIERS.map((tier) => (
                <option key={tier} value={tier}>{statusLabel(tier)}</option>
              ))}
            </select>
            <button className="primary" onClick={handlePromote} disabled={promoting || !promotePhone.trim()}>
              {promoting ? t('common.saving') : t('page.staff.promote_button')}
            </button>
          </div>
        </div>
      )}

      {err && <div className="error-box">{err}</div>}
      <Table<UserAccount>
        rows={staffRows}
        columns={columns}
        rowKey={(u) => u.user_id}
        loading={loading}
        empty={t('page.staff.empty')}
      />

      <EditModal
        open={editing !== null}
        title={editing ? t('common.modal_edit', { noun: t('noun.staff'), id: editing.user_id }) : ''}
        initial={editing ? flattenForEdit(editing.phone, editProfile) : {}}
        fields={USER_FIELDS}
        loading={editLoading}
        loadError={editError}
        onRetry={reloadEditProfile}
        onSave={(patch) => handleSave(editing!, patch)}
        onClose={() => setEditing(null)}
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.staff'), id: deleting.user_id }) : ''}
        message={deleting ? t('page.users.delete_body', { name: deleting.profile?.full_name ?? deleting.phone }) : ''}
        onConfirm={() => handleDelete(deleting!.user_id)}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}
