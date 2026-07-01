/**
 * City Guide admin page.
 *
 * Manages place entries that appear as map pins in the mobile app's
 * "City Guide" section (bottom of the Community screen). Every entry can
 * have a name (4 languages), coordinates, phone number, and a link.
 *
 * Uses the same backend endpoints as the Community Directory
 * (/api/community, /api/admin/community/:id) because both features share
 * the city_directory_entries table.
 */
import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api, describeError } from '../lib/api'
import type { CommunityEntry } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import EditModal, { type FieldSpec } from '../components/EditModal'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'

type Resp = { success: true; items: CommunityEntry[] }

const CITY_GUIDE_FIELDS: FieldSpec[] = [
  { key: 'name',          label: 'Place Name (EN)',    labelKey: 'field.name_en',        type: 'text',     required: true },
  { key: 'name_ar',       label: 'Place Name (AR)',    labelKey: 'field.name_ar',        type: 'text',     dir: 'rtl' },
  { key: 'name_sorani',   label: 'Place Name (Sorani)',labelKey: 'field.name_sorani',    type: 'text',     dir: 'rtl' },
  { key: 'name_badini',   label: 'Place Name (Badini)',labelKey: 'field.name_badini',    type: 'text',     dir: 'rtl' },
  { key: 'category',      label: 'Category',           labelKey: 'field.category',       type: 'text',     required: true },
  { key: 'city',          label: 'City',               labelKey: 'field.city',           type: 'text' },
  { key: 'address',       label: 'Address',            labelKey: 'field.address',        type: 'text' },
  { key: 'phone',         label: 'Phone Number',       labelKey: 'field.phone',          type: 'text' },
  { key: 'website',       label: 'Link / Website',     labelKey: 'field.website',        type: 'text' },
  { key: 'latitude',      label: 'Latitude',           labelKey: 'field.latitude',       type: 'text',     required: true },
  { key: 'longitude',     label: 'Longitude',          labelKey: 'field.longitude',      type: 'text',     required: true },
  { key: 'description',   label: 'Description (EN)',   labelKey: 'field.description_en', type: 'textarea', rows: 3 },
  { key: 'description_ar',label: 'Description (AR)',   labelKey: 'field.description_ar', type: 'textarea', rows: 3, dir: 'rtl' },
]

export default function CityGuidePage() {
  const [resp, setResp] = useState<Resp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
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
      .get<Resp>('/api/community', {
        params: { q: q || undefined, limit: 200 },
      })
      .then((res) => { if (!cancelled) setResp(res.data) })
      .catch((e) => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [q, refreshTick])

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/community/${id}`, patch)
      toast.success(`Place #${id} saved.`)
      setRefreshTick((n) => n + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>('/api/admin/community', data)
      toast.success(`Place #${res.data.id} created.`)
      setRefreshTick((n) => n + 1)
    },
    [toast],
  )

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/community/${id}`)
      toast.success(`Place #${id} deleted.`)
      setDeleting(null)
      setRefreshTick((n) => n + 1)
    },
    [toast],
  )

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const items = resp?.items ?? []
  const withCoords = items.filter(
    (e) => e.latitude !== null && e.latitude !== undefined && e.latitude !== '' &&
           e.longitude !== null && e.longitude !== undefined && e.longitude !== '',
  )

  const columns: Column<CommunityEntry>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (e) => <strong>#{e.id}</strong> },
    {
      key: 'name', header: 'Place', cell: (e) => (
        <div className="cell-stack">
          <strong>{e.name}</strong>
          {e.name_ar && <span className="muted" dir="rtl">{e.name_ar}</span>}
        </div>
      ),
    },
    { key: 'cat',  header: 'Category', cell: (e) => e.category },
    { key: 'city', header: t('col.city'),    cell: (e) => e.city ?? <span className="muted">—</span> },
    {
      key: 'coords', header: 'Coordinates',
      cell: (e) => (e.latitude && e.longitude)
        ? <code style={{ fontSize: '11px' }}>{Number(e.latitude).toFixed(4)}, {Number(e.longitude).toFixed(4)}</code>
        : <span className="muted" style={{ color: '#e57373' }}>⚠ no coords</span>,
    },
    {
      key: 'phone', header: t('col.phone'),
      cell: (e) => e.phone
        ? <a href={`tel:${e.phone}`} style={{ color: '#4caf50' }}>{e.phone}</a>
        : <span className="muted">—</span>,
    },
    {
      key: 'link', header: 'Link',
      cell: (e) => e.website
        ? <a href={e.website} target="_blank" rel="noreferrer">open ↗</a>
        : <span className="muted">—</span>,
    },
    {
      key: 'actions', header: t('common.actions'), width: '200px',
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
      {/* ── header ─────────────────────────────────────────────────────── */}
      <div className="page-head">
        <div>
          <h1 style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <span style={{ fontSize: '1.4rem' }}>🗺️</span>
            {t('nav.city_guide')}
          </h1>
          <p className="muted">
            {resp
              ? t('common.city_summary', { n: items.length, c: withCoords.length })
              : t('common.loading')}
          </p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t('common.city_search')}
            style={{ width: '200px' }}
          />
          <button onClick={() => setCreating(true)}>{t('common.city_add_place')}</button>
        </div>
      </div>

      {/* ── coord warning ───────────────────────────────────────────────── */}
      {!loading && items.length > 0 && withCoords.length < items.length && (
        <div
          style={{
            padding: '10px 16px',
            background: 'rgba(229,115,115,0.1)',
            border: '1px solid rgba(229,115,115,0.3)',
            borderRadius: '8px',
            fontSize: '13px',
            color: '#e57373',
          }}
        >
          ⚠ {items.length - withCoords.length} place(s) are missing coordinates — they won't appear on the app map.
        </div>
      )}

      {err && <div className="error-box">{err}</div>}

      <Table<CommunityEntry>
        rows={items}
        columns={columns}
        rowKey={(e) => e.id}
        loading={loading}
        empty={t('common.city_empty')}
      />

      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? 'Add new place' : editing ? `Edit place #${editing.id}` : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={CITY_GUIDE_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />

      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? `Delete place #${deleting.id}?` : ''}
        message={deleting ? `Remove "${deleting.name}" from the city guide?` : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}
