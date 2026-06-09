import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api, describeError } from '../lib/api'
import { roleLabel, type UsersListResp, type UserAccount } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import StatusCell from '../components/StatusCell'
import EditModal, { type FieldSpec } from '../components/EditModal'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'
import { downloadCsv, type CsvColumn } from '../lib/csv'
import { formatPhone } from '../lib/phone'

const PER_PAGE = 20

const ROLE_LABELS = ['donor', 'beneficiary', 'volunteer', 'none']
const GENDER_OPTIONS = ['', 'Male', 'Female', 'Other']

// Phase 18: editable fields. role / active / is_admin live in their own
// dedicated /status endpoints (Phase 9 inline dropdowns), so they're omitted
// from this form to avoid two ways to set the same column.
const USER_FIELDS: FieldSpec[] = [
  { key: 'phone',           label: 'Phone', labelKey: 'field.phone',           type: 'text', required: true },
  { key: 'full_name',       label: 'Full name', labelKey: 'field.full_name',       type: 'text' },
  { key: 'gender',          label: 'Gender', labelKey: 'field.gender',          type: 'select', options: GENDER_OPTIONS },
  { key: 'address',         label: 'Address', labelKey: 'field.address',         type: 'textarea', rows: 2 },
  { key: 'profile_picture', label: 'Profile picture', labelKey: 'field.profile_picture', type: 'file', full: true },
]

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
    address:         u.profile?.address ?? '',
    profile_picture: u.profile?.profile_picture ?? '',
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
  const [refreshTick, setRefreshTick] = useState(0)
  const toast = useToast()
  const { t } = useI18n()

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

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/users/${id}`, patch)
      toast.success(t('toast.saved', { noun: `${t('noun.user')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
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

  const exportCsv = () => {
    const rows = resp?.data ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`users-${new Date().toISOString().slice(0, 10)}.csv`, rows, USER_CSV_COLUMNS)
  }

  const columns: Column<UserAccount>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (u) => <strong>#{u.user_id}</strong> },
    {
      key: 'name',
      header: t('col.name'),
      cell: (u) => u.profile?.full_name ?? <span className="muted">—</span>,
    },
    { key: 'phone', header: t('col.phone'), cell: (u) => formatPhone(u.phone) },
    {
      key: 'role',
      header: t('col.role'),
      cell: (u) => (
        <StatusCell
          value={roleLabel(u.role_id)}
          allowed={ROLE_LABELS}
          onSave={(next) =>
            api.post(`/api/admin/users/${u.user_id}/role`, { role_id: roleLabelToId(next) })
          }
          label={`User #${u.user_id} role`}
        />
      ),
    },
    {
      key: 'active',
      header: t('col.active'),
      cell: (u) => (
        <StatusCell
          value={u.active === 1 ? 'yes' : 'no'}
          allowed={['yes', 'no']}
          onSave={(next) =>
            api.post(`/api/admin/users/${u.user_id}/active`, { active: next === 'yes' ? 1 : 0 })
          }
          label={`User #${u.user_id} active`}
        />
      ),
    },
    {
      key: 'admin',
      header: t('col.admin'),
      cell: (u) => (
        <StatusCell
          value={u.is_admin === 1 ? 'admin' : 'user'}
          allowed={['admin', 'user']}
          onSave={(next) =>
            api.post(`/api/admin/users/${u.user_id}/admin`, { is_admin: next === 'admin' ? 1 : 0 })
          }
          label={`User #${u.user_id} admin`}
        />
      ),
    },
    {
      key: 'created',
      header: t('col.created'),
      cell: (u) => <span className="muted">{u.created_at?.slice(0, 10)}</span>,
    },
    {
      key: 'actions', header: '', width: '170px',
      cell: (u) => (
        <>
          <Link className="row-edit-btn" to={`/detail/users/${u.user_id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(u)}>{t('common.edit')}</button>
          <button className="row-delete-btn" onClick={() => setDeleting(u)}>{t('common.delete')}</button>
        </>
      ),
    },
  ]

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
          <button className="secondary" onClick={exportCsv}>{t('common.export_csv')}</button>
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
        onSave={(patch) => handleSave(editing!.user_id, patch)}
        onClose={() => setEditing(null)}
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
