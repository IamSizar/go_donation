// TrashPage — Phase 7 (G-06 / A-16). The recovery bin for every admin delete.
//
// Deletes across the dashboard no longer destroy rows; the backend snapshots
// each one into trash_items as a JSON document. Here an admin can Restore a
// record (re-inserted from that snapshot) or permanently Purge it — purge is
// PIN-gated (re-enter your password) and only offered to the Super-Admin.
import { useCallback, useEffect, useState } from 'react'
import { api, describeError, canExportData, isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import Table, { type Column } from '../components/Table'

type TrashItem = {
  id: number
  source_table: string
  row_id: number
  deleted_by: number | null
  deleted_by_name: string | null
  deleted_at: string
  payload: Record<string, unknown>
}

// Friendly module label per source table, resolved via existing nav keys so it
// localizes; falls back to the raw table name (a technical DB value).
const MODULE_TKEY: Record<string, string> = {
  partners: 'nav.partners',
  media_posts: 'nav.media',
  city_directory_entries: 'nav.city_guide',
  marriage_profiles: 'nav.marriage',
  marketplace_products: 'nav.marketplace',
  marketplace_orders: 'nav.marketplace',
  beneficiary_cases: 'nav.beneficiary',
  beneficiary_project_requests: 'nav.beneficiary',
  sponsorships: 'nav.sponsorships',
  in_kind_donations: 'nav.in_kind',
  support_tickets: 'nav.support',
  donations: 'nav.donations',
  volunteer_applications: 'nav.volunteers',
  campaigns: 'nav.campaigns',
  users: 'nav.users',
  volunteer_missions: 'nav.missions',
}

// Pull a human-readable label out of the snapshot to help identify the record.
function previewOf(payload: Record<string, unknown>): string {
  const cand = ['full_name', 'title', 'name', 'product_name', 'reference', 'ref', 'username', 'phone', 'email']
  for (const k of cand) {
    const v = payload?.[k]
    if (typeof v === 'string' && v.trim()) return v
  }
  return ''
}

export default function TrashPage() {
  const { user } = useAuth()
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<TrashItem[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<number | null>(null)

  const allowed = canExportData(user)
  const canPurge = isSuperAdmin(user) || user?.is_admin === 1

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const { data } = await api.get<{ items: TrashItem[] }>('/api/admin/trash')
      setItems(data.items ?? [])
      setErr(null)
    } catch (e) {
      setErr(describeError(e))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { if (allowed) void load() }, [allowed, load])

  const restore = async (it: TrashItem) => {
    if (busyId) return
    setBusyId(it.id)
    try {
      await api.post(`/api/admin/trash/${it.id}/restore`)
      toast.success(t('page.trash.restored'))
      await load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyId(null)
    }
  }

  const purge = async (it: TrashItem) => {
    if (busyId) return
    const pin = window.prompt(t('page.trash.purge_prompt'))
    if (pin == null) return
    if (!pin.trim()) { toast.error(t('export.pin_required')); return }
    setBusyId(it.id)
    try {
      await api.post(`/api/admin/trash/${it.id}/purge`, { password: pin })
      toast.success(t('page.trash.purged'))
      await load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyId(null)
    }
  }

  if (!allowed) {
    return (
      <div className="stack">
        <div className="error-box">{t('page.trash.no_access')}</div>
      </div>
    )
  }

  const columns: Column<TrashItem>[] = [
    { key: 'module', header: t('page.trash.col_module'), cell: (it) => (
      MODULE_TKEY[it.source_table]
        ? <strong>{t(MODULE_TKEY[it.source_table])}</strong>
        : <code style={{ background: 'transparent', padding: 0 }}>{it.source_table}</code>
    ) },
    { key: 'record', header: t('page.trash.col_record'), cell: (it) => (
      <div className="cell-stack">
        <strong>#{it.row_id}</strong>
        {previewOf(it.payload) && <span className="muted">{previewOf(it.payload)}</span>}
      </div>
    ) },
    { key: 'by', header: t('page.trash.col_deleted_by'), cell: (it) => it.deleted_by_name || <span className="muted">—</span> },
    { key: 'at', header: t('page.trash.col_deleted_at'), cell: (it) => <span className="muted">{it.deleted_at?.slice(0, 16).replace('T', ' ')}</span> },
    { key: 'actions', header: t('common.actions'), cell: (it) => (
      <div className="row" style={{ gap: 6, justifyContent: 'flex-end' }}>
        <button className="secondary" disabled={busyId === it.id} onClick={() => restore(it)}>
          {t('action.restore')}
        </button>
        {canPurge && (
          <button className="danger" disabled={busyId === it.id} onClick={() => purge(it)}>
            {t('action.purge')}
          </button>
        )}
      </div>
    ) },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.trash.title')}</h1>
          <p className="muted">
            {loading ? t('common.loading') : t('page.trash.subtitle', { n: items.length })}
          </p>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<TrashItem>
        rows={items}
        columns={columns}
        rowKey={(it) => it.id}
        loading={loading}
        empty={t('page.trash.empty')}
      />
    </div>
  )
}
