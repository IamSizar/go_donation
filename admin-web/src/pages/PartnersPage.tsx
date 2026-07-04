import { useCallback, useEffect, useState } from 'react'
import RowDeleteButton from '../components/RowDeleteButton'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError, assetUrl } from '../lib/api'
import type { Partner } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import StatusCell from '../components/StatusCell'
import EditModal, { type FieldSpec } from '../components/EditModal'
import BulkBar from '../components/BulkBar'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { useSelection } from '../lib/useSelection'
import { downloadCsv, type CsvColumn } from '../lib/csv'

type Resp = { success: true; items: Partner[] }

const STATUSES = ['all', 'pending', 'active', 'hidden']
const EDITABLE_STATUSES = STATUSES.filter((s) => s !== 'all')

// Field spec for the edit modal. Kept here (next to the page) because every
// resource has its own column set.
const PARTNER_FIELDS: FieldSpec[] = [
  { key: 'name',                label: 'Name (EN)', labelKey: 'field.name_en',           type: 'text',     required: true },
  { key: 'name_ar',             label: 'Name (AR)', labelKey: 'field.name_ar',           type: 'text',     dir: 'rtl' },
  { key: 'name_sorani',         label: 'Name (Sorani)', labelKey: 'field.name_sorani',       type: 'text',     dir: 'rtl' },
  { key: 'name_badini',         label: 'Name (Badini)', labelKey: 'field.name_badini',       type: 'text',     dir: 'rtl' },
  { key: 'partner_type',        label: 'Type', labelKey: 'field.type',                type: 'text' },
  { key: 'status',              label: 'Status', labelKey: 'field.status',              type: 'select',   options: EDITABLE_STATUSES },
  { key: 'contact_phone',       label: 'Contact phone', labelKey: 'field.contact_phone',       type: 'text' },
  { key: 'website',             label: 'Website', labelKey: 'field.website',             type: 'text' },
  { key: 'logo_path',           label: 'Logo', labelKey: 'field.logo',                type: 'file', full: true },
  { key: 'description',         label: 'Description (EN)', labelKey: 'field.description_en',    type: 'textarea', rows: 3 },
  { key: 'description_ar',      label: 'Description (AR)', labelKey: 'field.description_ar',    type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'description_sorani',  label: 'Description (Sorani)', labelKey: 'field.description_sorani',type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'description_badini',  label: 'Description (Badini)', labelKey: 'field.description_badini',type: 'textarea', rows: 3, dir: 'rtl' },
]

const CSV_COLUMNS: CsvColumn<Partner>[] = [
  { header: 'id', get: (p) => p.id },
  { header: 'name', get: (p) => p.name },
  { header: 'name_ar', get: (p) => p.name_ar },
  { header: 'name_sorani', get: (p) => p.name_sorani },
  { header: 'name_badini', get: (p) => p.name_badini },
  { header: 'partner_type', get: (p) => p.partner_type },
  { header: 'contact_phone', get: (p) => p.contact_phone },
  { header: 'website', get: (p) => p.website },
  { header: 'status', get: (p) => p.status },
]

export default function PartnersPage() {
  const [status, setStatus] = useState('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<Resp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<Partner | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<Partner | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  const toast = useToast()
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<Partner>((p) => p.id)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setErr(null)
    api
      .get<Resp>('/api/partners', { params: { status, q: q || undefined, limit: 100 } })
      .then((res) => {
        if (!cancelled) setResp(res.data)
      })
      .catch((e) => {
        if (!cancelled) setErr(describeError(e))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [status, q, refreshTick])

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/partners/${id}`, patch)
      toast.success(t('toast.saved', { noun: `${t('noun.partner')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(`/api/admin/partners`, data)
      toast.success(t('toast.created', { noun: `${t('noun.partner')} #${res.data.id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const applyBulkStatus = useCallback(
    async (newStatus: string): Promise<{ ok: number; fail: number }> => {
      const ids = [...sel.selected]
      const results = await Promise.allSettled(
        ids.map((id) => api.post(`/api/admin/partners/${id}/status`, { status: newStatus })),
      )
      const ok = results.filter((r) => r.status === 'fulfilled').length
      const fail = results.length - ok
      sel.clear()
      setRefreshTick((t) => t + 1)
      return { ok, fail }
    },
    [sel],
  )

  const applyBulkDelete = useCallback(
    async (): Promise<{ ok: number; fail: number }> => {
      const ids = [...sel.selected]
      const results = await Promise.allSettled(
        ids.map((id) => api.delete(`/api/admin/partners/${id}`)),
      )
      const ok = results.filter((r) => r.status === 'fulfilled').length
      sel.clear()
      setRefreshTick((t) => t + 1)
      return { ok, fail: results.length - ok }
    },
    [sel],
  )

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/partners/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.partner')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) {
      toast.info(t('common.nothing_to_export'))
      return
    }
    downloadCsv(`partners-${new Date().toISOString().slice(0, 10)}.csv`, rows, CSV_COLUMNS)
  }

  const columns: Column<Partner>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (p) => <strong>#{p.id}</strong> },
    {
      key: 'logo',
      header: '',
      width: '56px',
      cell: (p) =>
        p.logo_path ? (
          <img src={assetUrl(p.logo_path)} alt="" className="thumb" />
        ) : (
          <div className="thumb thumb-empty" />
        ),
    },
    {
      key: 'name',
      header: t('col.name'),
      cell: (p) => (
        <div className="cell-stack">
          <strong>{p.name}</strong>
          {p.name_ar && <span className="muted">{p.name_ar}</span>}
        </div>
      ),
    },
    { key: 'type', header: t('col.type'), cell: (p) => p.partner_type ?? <span className="muted">—</span> },
    {
      key: 'website',
      header: t('col.website'),
      cell: (p) =>
        p.website ? (
          <a href={p.website} target="_blank" rel="noreferrer">{p.website}</a>
        ) : (
          <span className="muted">—</span>
        ),
    },
    { key: 'phone', header: t('col.phone'), cell: (p) => p.contact_phone ?? <span className="muted">—</span> },
    {
      key: 'status',
      header: t('col.status'),
      cell: (p) => (
        <StatusCell
          value={p.status}
          allowed={EDITABLE_STATUSES}
          onSave={(next) => api.post(`/api/admin/partners/${p.id}/status`, { status: next })}
          label={`Partner #${p.id}`}
        />
      ),
    },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '170px',
      cell: (p) => (
        <>
          <Link className="row-edit-btn" to={`/detail/partners/${p.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(p)}>{t('common.edit')}</button>
          <RowDeleteButton onClick={() => setDeleting(p)} />
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.partners.title')}</h1>
          <p className="muted">{resp ? `${resp.items.length} ${t('common.shown')}` : t('common.loading')}</p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); sel.clear() }}
            placeholder={t('page.partners.search_placeholder')}
            style={{ width: '200px' }}
          />
          <select value={status} onChange={(e) => { setStatus(e.target.value); sel.clear() }} style={{ width: 'auto' }}>
            {STATUSES.map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}
          </select>
          <ExportCsvButton onExport={exportCsv} />
          <button onClick={() => setCreating(true)}>{t('page.partners.new')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<Partner>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(p) => p.id}
        loading={loading}
        empty={t('empty.partners')}
        selectable={sel.forRows(resp?.items ?? [])}
      />
      <BulkBar
        count={sel.count}
        allowed={EDITABLE_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun="partners"
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.partner'), id: deleting.id }) : ''}
        message={deleting ? `${t('common.confirm_delete_body', { name: deleting.name })} ${t('common.cannot_undo')}` : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.partner') }) : editing ? t('common.modal_edit', { noun: t('noun.partner'), id: editing.id }) : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={PARTNER_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
    </div>
  )
}
