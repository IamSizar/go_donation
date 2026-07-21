/**
 * Marriage Posts page (Note #35, part 2) — the dedicated public-posting
 * control panel for the Marriage section the client asked for. Reuses the
 * existing media_posts CRUD/table (post_type='marriage' has been a valid,
 * separately-fed value since migration 011 — the general "Our Work" feed
 * already excludes it), just scoped to that one type instead of exposing the
 * generic Media page's type selector.
 */
import { useCallback, useEffect, useState } from 'react'
import RowDeleteButton from '../components/RowDeleteButton'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError, assetUrl } from '../lib/api'
import type { MediaPost } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import StatusCell from '../components/StatusCell'
import EditModal, { type FieldSpec } from '../components/EditModal'
import BulkBar from '../components/BulkBar'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { useSelection } from '../lib/useSelection'
import { type CsvColumn } from '../lib/csv'

const POST_CSV_COLUMNS: CsvColumn<MediaPost>[] = [
  { header: 'id', get: (m) => m.id },
  { header: 'title', get: (m) => m.title },
  { header: 'title_ar', get: (m) => m.title_ar },
  { header: 'status', get: (m) => m.status },
  { header: 'event_date', get: (m) => m.event_date },
  { header: 'media_url', get: (m) => m.media_url },
  { header: 'link_url', get: (m) => m.link_url },
  { header: 'created_at', get: (m) => m.created_at },
]

type Resp = { success: true; items: MediaPost[] }

const STATUSES = ['all', 'draft', 'published', 'hidden']
const EDITABLE_STATUSES = STATUSES.filter((s) => s !== 'all')

const MARRIAGE_POST_FIELDS: FieldSpec[] = [
  { key: 'title',        label: 'Title (EN)', labelKey: 'field.title_en',    type: 'text',     required: true },
  { key: 'title_ar',     label: 'Title (AR)', labelKey: 'field.title_ar',    type: 'text',     dir: 'rtl' },
  { key: 'title_sorani', label: 'Title (Sorani)', labelKey: 'field.title_sorani', type: 'text', dir: 'rtl' },
  { key: 'title_badini', label: 'Title (Badini)', labelKey: 'field.title_badini', type: 'text', dir: 'rtl' },
  { key: 'status',       label: 'Status', labelKey: 'field.status',        type: 'select',   options: EDITABLE_STATUSES },
  { key: 'media_url',    label: 'Media', labelKey: 'field.media',         type: 'file', full: true },
  { key: 'gallery',      label: 'Gallery', labelKey: 'field.gallery',       type: 'gallery', full: true },
  { key: 'link_url',     label: 'Link URL', labelKey: 'field.link_url',      type: 'text' },
  { key: 'event_date',   label: 'Event date', labelKey: 'field.event_date',    type: 'text', placeholder: 'YYYY-MM-DD' },
  { key: 'body',         label: 'Body (EN)', labelKey: 'field.body_en',      type: 'textarea', rows: 4 },
  { key: 'body_ar',      label: 'Body (AR)', labelKey: 'field.body_ar',      type: 'textarea', rows: 4, dir: 'rtl' },
  { key: 'body_sorani',  label: 'Body (Sorani)', labelKey: 'field.body_sorani',  type: 'textarea', rows: 4, dir: 'rtl' },
  { key: 'body_badini',  label: 'Body (Badini)', labelKey: 'field.body_badini',  type: 'textarea', rows: 4, dir: 'rtl' },
]

export default function MarriagePostsPage() {
  const [status, setStatus] = useState('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<Resp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<MediaPost | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<MediaPost | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  const toast = useToast()
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<MediaPost>((m) => m.id)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setErr(null)
    api
      .get<Resp>('/api/media', { params: { status, type: 'marriage', q: q || undefined, limit: 100 } })
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

  const trimDate = (p: Record<string, unknown>): Record<string, unknown> => {
    const out: Record<string, unknown> = { ...p, post_type: 'marriage' }
    if (typeof out.event_date === 'string' && out.event_date.length > 10) {
      out.event_date = out.event_date.slice(0, 10)
    }
    return out
  }

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/media/${id}`, trimDate(patch))
      toast.success(t('toast.saved', { noun: `${t('noun.marriage_post')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast, t],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(`/api/admin/media`, trimDate(data))
      toast.success(t('toast.created', { noun: `${t('noun.marriage_post')} #${res.data.id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast, t],
  )

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const applyBulkStatus = useCallback(
    async (newStatus: string) => {
      const ids = [...sel.selected]
      const results = await Promise.allSettled(
        ids.map((id) => api.post(`/api/admin/media/${id}/status`, { status: newStatus })),
      )
      const ok = results.filter((r) => r.status === 'fulfilled').length
      sel.clear()
      setRefreshTick((t) => t + 1)
      return { ok, fail: results.length - ok }
    },
    [sel],
  )

  const applyBulkDelete = useCallback(async () => {
    const ids = [...sel.selected]
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/media/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/media/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.marriage_post')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast, t],
  )

  const columns: Column<MediaPost>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (m) => <strong>#{m.id}</strong> },
    {
      key: 'media',
      header: '',
      width: '56px',
      cell: (m) =>
        m.media_url ? (
          <img src={assetUrl(m.media_url)} alt="" className="thumb" />
        ) : (
          <div className="thumb thumb-empty" />
        ),
    },
    {
      key: 'title',
      header: t('col.title'),
      cell: (m) => (
        <div className="cell-stack">
          <strong>{m.title}</strong>
          {m.title_ar && <span className="muted">{m.title_ar}</span>}
        </div>
      ),
    },
    {
      key: 'event',
      header: t('col.event_date'),
      cell: (m) => (m.event_date ? <span className="muted">{m.event_date.slice(0, 10)}</span> : <span className="muted">—</span>),
    },
    {
      key: 'status',
      header: t('col.status'),
      cell: (m) => (
        <StatusCell
          value={m.status}
          allowed={EDITABLE_STATUSES}
          onSave={(next) => api.post(`/api/admin/media/${m.id}/status`, { status: next })}
          label={`${t('noun.marriage_post')} #${m.id}`}
        />
      ),
    },
    {
      key: 'created',
      header: t('col.created'),
      cell: (m) => <span className="muted">{m.created_at?.slice(0, 10)}</span>,
    },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '170px',
      cell: (m) => (
        <>
          <Link className="row-edit-btn" to={`/detail/media/${m.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(m)}>{t('common.edit')}</button>
          <RowDeleteButton onClick={() => setDeleting(m)} />
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.marriage_posts.title')}</h1>
          <p className="muted">
            {resp ? `${resp.items.length} ${t('common.shown')}` : t('common.loading')}
          </p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); sel.clear() }}
            placeholder={t('page.media.search_placeholder')}
            style={{ width: '200px' }}
          />
          <select value={status} onChange={(e) => { setStatus(e.target.value); sel.clear() }} style={{ width: 'auto' }}>
            {STATUSES.map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}
          </select>
          <ExportCsvButton
            rows={resp?.items ?? []}
            columns={POST_CSV_COLUMNS}
            filenameBase="marriage_posts"
            title={t('page.marriage_posts.title')}
            module="marriage"
          />
          <button onClick={() => setCreating(true)}>{t('page.marriage_posts.new')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<MediaPost>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(m) => m.id}
        loading={loading}
        empty={t('page.marriage_posts.empty')}
        selectable={sel.forRows(resp?.items ?? [])}
      />
      <BulkBar
        count={sel.count}
        allowed={EDITABLE_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun="posts"
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.marriage_post'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body', { name: deleting.title }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.marriage_post') }) : editing ? t('common.modal_edit', { noun: t('noun.marriage_post'), id: editing.id }) : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={MARRIAGE_POST_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
    </div>
  )
}
