/**
 * Admin Marriage Meeting Requests page (Note #35) — the inbox a "request a
 * meeting" tap in the app used to vanish into with no staff visibility at
 * all. Staff Approve (opens a staff-mediated chat thread, pending the
 * profile owner's accept) or Decline each pending request.
 */
import { useCallback, useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import Table, { type Column } from '../components/Table'

type MeetingRequest = {
  id: number
  from_user_id: number
  from_name: string | null
  from_phone: string | null
  profile_id: number
  profile_code: string
  owner_user_id: number
  owner_name: string | null
  owner_phone: string | null
  message: string | null
  status: 'pending' | 'approved' | 'declined'
  thread_id: number | null
  created_at: string
  decided_at: string | null
}

function name(n: string | null, id: number, t: (key: string, vars?: Record<string, string | number>) => string): string {
  return n && n.trim() ? n : t('common.user_ref', { id })
}

function StatusBadge({ status }: { status: string }) {
  const tone = status === 'approved' ? 'success' : status === 'declined' ? 'danger' : 'warning'
  return <span className={`badge tone-${tone}`}>{status}</span>
}

export default function MarriageMeetingRequestsPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<MeetingRequest[]>([])
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<number | null>(null)

  const load = useCallback(() => {
    setLoading(true)
    api
      .get<{ items: MeetingRequest[] }>('/api/admin/marriage/meeting-requests')
      .then((res) => { setItems(res.data.items ?? []); setErr(null) })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }, [])
  useEffect(load, [load])

  const approve = async (r: MeetingRequest) => {
    setBusyId(r.id)
    try {
      await api.post(`/api/admin/marriage/meeting-requests/${r.id}/approve`)
      toast.success(t('page.marriage_requests.approved'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyId(null)
    }
  }

  const decline = async (r: MeetingRequest) => {
    setBusyId(r.id)
    try {
      await api.post(`/api/admin/marriage/meeting-requests/${r.id}/decline`)
      toast.success(t('page.marriage_requests.declined'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyId(null)
    }
  }

  const columns: Column<MeetingRequest>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (r) => <strong>#{r.id}</strong> },
    { key: 'from', header: t('page.marriage_requests.from'), cell: (r) => name(r.from_name, r.from_user_id, t) },
    { key: 'profile', header: t('page.marriage_requests.about_profile'), cell: (r) => r.profile_code },
    { key: 'owner', header: t('page.marriage_requests.profile_owner'), cell: (r) => name(r.owner_name, r.owner_user_id, t) },
    {
      key: 'message',
      header: t('field.message'),
      cell: (r) => r.message ? <span>{r.message}</span> : <span className="muted">—</span>,
    },
    { key: 'status', header: t('col.status'), cell: (r) => <StatusBadge status={r.status} /> },
    { key: 'created', header: t('col.created'), cell: (r) => <span className="muted">{r.created_at?.slice(0, 10)}</span> },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '200px',
      cell: (r) =>
        r.status === 'pending' ? (
          <div className="row" style={{ gap: 8 }}>
            <button onClick={() => approve(r)} disabled={busyId === r.id}>{t('page.marriage_requests.approve')}</button>
            <button className="secondary" onClick={() => decline(r)} disabled={busyId === r.id}>{t('page.marriage_requests.decline')}</button>
          </div>
        ) : (
          <span className="muted">{r.decided_at?.slice(0, 10) ?? '—'}</span>
        ),
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('nav.marriage_requests')}</h1>
          <p className="muted">{t('page.marriage_requests.subtitle')}</p>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<MeetingRequest>
        rows={items}
        columns={columns}
        rowKey={(r) => r.id}
        loading={loading}
        empty={t('page.marriage_requests.empty')}
      />
    </div>
  )
}
