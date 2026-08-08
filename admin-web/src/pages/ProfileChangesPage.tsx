import { useCallback, useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import Table, { type Column } from '../components/Table'
import PageHead from '../components/PageHead'
import ActionsMenu from '../components/ActionsMenu'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'
import { fmtId } from '../lib/formatId'
import { formatDateTime } from '../lib/dates'

// #22 — users' own name / photo changes wait here until staff approve them.
// The live profile is untouched until approval, so rejecting simply drops the
// request and nothing ever displayed the unapproved value.
type ChangeRequest = {
  id: number
  user_id: number
  user_name: string
  user_phone: string
  field: string
  old_value: string
  new_value: string
  status: string
  created_at: string
  decided_at: string | null
}

export default function ProfileChangesPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<ChangeRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [status, setStatus] = useState('pending')
  const [busyId, setBusyId] = useState<number | null>(null)

  const load = useCallback(() => {
    setLoading(true)
    setErr(null)
    api
      .get<{ items: ChangeRequest[] }>('/api/admin/profile-changes', { params: { status } })
      .then((r) => setItems(r.data.items ?? []))
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }, [status])

  useEffect(load, [load])

  const decide = async (r: ChangeRequest, approve: boolean) => {
    setBusyId(r.id)
    try {
      await api.post(`/api/admin/profile-changes/${r.id}/decide`, { approve })
      toast.success(approve ? t('profileChanges.approved') : t('profileChanges.rejected'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyId(null)
    }
  }

  // A photo change is a path, not text — show it as an image so the reviewer
  // is judging the actual picture rather than a filename.
  const renderValue = (field: string, value: string) => {
    if (!value) return <span className="muted">—</span>
    if (field === 'profile_picture') {
      return <img src={value} alt="" style={{ height: 44, borderRadius: 8 }} />
    }
    return <span>{value}</span>
  }

  const columns: Column<ChangeRequest>[] = [
    { key: 'id', header: t('col.id'), width: '70px', cell: (r) => <strong>{fmtId(r.id)}</strong> },
    {
      key: 'user',
      header: t('col.user'),
      cell: (r) => (
        <div className="cell-stack">
          <span>{r.user_name || fmtId(r.user_id)}</span>
          <span className="muted">{r.user_phone}</span>
        </div>
      ),
    },
    { key: 'field', header: t('col.field'), cell: (r) => t(`profileChanges.field_${r.field}`) },
    { key: 'old', header: t('profileChanges.old'), cell: (r) => renderValue(r.field, r.old_value) },
    { key: 'new', header: t('profileChanges.new'), cell: (r) => renderValue(r.field, r.new_value) },
    { key: 'created', header: t('col.created'), cell: (r) => <span className="muted">{formatDateTime(r.created_at)}</span> },
    { key: 'status', header: t('col.status'), cell: (r) => <span className="muted">{t(`status.${r.status}`)}</span> },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '150px',
      cell: (r) =>
        r.status !== 'pending' ? (
          <span className="muted">—</span>
        ) : (
          <ActionsMenu
            items={[
              {
                key: 'approve',
                label: t('profileChanges.approve'),
                disabled: busyId === r.id,
                onClick: () => decide(r, true),
              },
              {
                key: 'reject',
                label: t('profileChanges.reject'),
                danger: true,
                disabled: busyId === r.id,
                onClick: () => decide(r, false),
              },
            ]}
          />
        ),
    },
  ]

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('nav.profile_changes')}</h1>
          <p className="muted">{t('profileChanges.subtitle')}</p>
        </div>
        <div className="row">
          <select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 'auto' }}>
            <option value="pending">{t('status.pending')}</option>
            <option value="approved">{t('status.approved')}</option>
            <option value="rejected">{t('status.rejected')}</option>
            <option value="all">{t('filter.all_statuses')}</option>
          </select>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}
      {!loading && <Table rows={items} columns={columns} rowKey={(r) => r.id} />}
    </div>
  )
}
