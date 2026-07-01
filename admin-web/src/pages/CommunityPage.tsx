import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError } from '../lib/api'
import type { CommunityEntry } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import EditModal, { type FieldSpec } from '../components/EditModal'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'
import { downloadCsv, type CsvColumn } from '../lib/csv'

const COMMUNITY_CSV_COLUMNS: CsvColumn<CommunityEntry>[] = [
  { header: 'id', get: (e) => e.id },
  { header: 'name', get: (e) => e.name },
  { header: 'name_ar', get: (e) => e.name_ar },
  { header: 'name_sorani', get: (e) => e.name_sorani },
  { header: 'name_badini', get: (e) => e.name_badini },
  { header: 'category', get: (e) => e.category },
  { header: 'city', get: (e) => e.city },
  { header: 'address', get: (e) => e.address },
  { header: 'phone', get: (e) => e.phone },
  { header: 'email', get: (e) => e.email },
  { header: 'website', get: (e) => e.website },
]

type Resp = { success: true; items: CommunityEntry[] }

const COMMUNITY_FIELDS: FieldSpec[] = [
  { key: 'name',                label: 'Name (EN)', labelKey: 'field.name_en',          type: 'text',     required: true },
  { key: 'name_ar',             label: 'Name (AR)', labelKey: 'field.name_ar',          type: 'text',     dir: 'rtl' },
  { key: 'name_sorani',         label: 'Name (Sorani)', labelKey: 'field.name_sorani',      type: 'text',     dir: 'rtl' },
  { key: 'name_badini',         label: 'Name (Badini)', labelKey: 'field.name_badini',      type: 'text',     dir: 'rtl' },
  { key: 'category',            label: 'Category', labelKey: 'field.category',           type: 'text',     required: true },
  { key: 'city',                label: 'City', labelKey: 'field.city',               type: 'text' },
  { key: 'address',             label: 'Address', labelKey: 'field.address',            type: 'text' },
  { key: 'phone',               label: 'Phone', labelKey: 'field.phone',              type: 'text' },
  { key: 'email',               label: 'Email', labelKey: 'field.email',              type: 'text' },
  { key: 'website',             label: 'Website', labelKey: 'field.website',            type: 'text' },
  { key: 'latitude',            label: 'Latitude', labelKey: 'field.latitude',           type: 'text' },
  { key: 'longitude',           label: 'Longitude', labelKey: 'field.longitude',          type: 'text' },
  { key: 'description',         label: 'Description (EN)', labelKey: 'field.description_en',   type: 'textarea', rows: 3 },
  { key: 'description_ar',      label: 'Description (AR)', labelKey: 'field.description_ar',   type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'description_sorani',  label: 'Description (Sorani)', labelKey: 'field.description_sorani', type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'description_badini',  label: 'Description (Badini)', labelKey: 'field.description_badini', type: 'textarea', rows: 3, dir: 'rtl' },
]

export default function CommunityPage() {
  const [resp, setResp] = useState<Resp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [city, setCity] = useState('')
  const [category, setCategory] = useState('')
  const [editing, setEditing] = useState<CommunityEntry | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<CommunityEntry | null>(null)
  const [q, setQ] = useState('')
  const [refreshTick, setRefreshTick] = useState(0)
  const toast = useToast()
  const { t } = useI18n()

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setErr(null)
    api
      .get<Resp>('/api/community', { params: { city: city || undefined, category: category || undefined, q: q || undefined, limit: 100 } })
      .then((res) => { if (!cancelled) setResp(res.data) })
      .catch((e) => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [city, category, q, refreshTick])

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/community/${id}`, patch)
      toast.success(t('toast.saved', { noun: `${t('noun.community_entry')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(`/api/admin/community`, data)
      toast.success(t('toast.created', { noun: `${t('noun.community_entry')} #${res.data.id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const exportCsv = () => {
    const rows = items
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`community-${new Date().toISOString().slice(0, 10)}.csv`, rows, COMMUNITY_CSV_COLUMNS)
  }

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/community/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.community_entry')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const items = resp?.items ?? []
  const cities = Array.from(new Set(items.map(i => i.city).filter(Boolean) as string[])).sort()
  const categories = Array.from(new Set(items.map(i => i.category))).sort()

  const columns: Column<CommunityEntry>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (e) => <strong>#{e.id}</strong> },
    {
      key: 'name', header: t('col.name'), cell: (e) => (
        <div className="cell-stack">
          <strong>{e.name}</strong>
          {e.name_ar && <span className="muted">{e.name_ar}</span>}
        </div>
      ),
    },
    { key: 'cat', header: t('col.category'), cell: (e) => e.category },
    { key: 'city', header: t('col.city'), cell: (e) => e.city ?? <span className="muted">—</span> },
    { key: 'addr', header: t('col.address'), cell: (e) => e.address ?? <span className="muted">—</span> },
    { key: 'phone', header: t('col.phone'), cell: (e) => e.phone ?? <span className="muted">—</span> },
    {
      key: 'web', header: t('col.website'),
      cell: (e) => e.website ? <a href={e.website} target="_blank" rel="noreferrer">open ↗</a> : <span className="muted">—</span>,
    },
    {
      key: 'actions', header: t('common.actions'), width: '170px',
      cell: (e) => (
        <>
          <Link className="row-edit-btn" to={`/detail/community/${e.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(e)}>{t('common.edit')}</button>
          <button className="row-delete-btn" onClick={() => setDeleting(e)}>{t('common.delete')}</button>
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.community.title')}</h1>
          <p className="muted">{resp ? `${items.length} ${t('common.shown')}` : t('common.loading')}</p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t('page.community.search_placeholder')}
            style={{ width: '200px' }}
          />
          <select value={category} onChange={e => setCategory(e.target.value)} style={{ width: 'auto' }}>
            <option value="">{t('filter.all_categories')}</option>
            {categories.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
          <select value={city} onChange={e => setCity(e.target.value)} style={{ width: 'auto' }}>
            <option value="">{t('filter.all_cities')}</option>
            {cities.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
          <ExportCsvButton onExport={exportCsv} />
          <button onClick={() => setCreating(true)}>{t('page.community.new')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<CommunityEntry> rows={items} columns={columns} rowKey={(e) => e.id} loading={loading} empty={t('empty.community')} />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.community_entry') }) : editing ? t('common.modal_edit', { noun: t('noun.community_entry'), id: editing.id }) : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={COMMUNITY_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.community_entry'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body', { name: deleting.name }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}
