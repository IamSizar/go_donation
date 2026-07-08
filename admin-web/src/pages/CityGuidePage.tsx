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
import { useCallback, useEffect, useMemo, useState } from 'react'
import RowDeleteButton from '../components/RowDeleteButton'
import { Link } from 'react-router-dom'
import { api, describeError } from '../lib/api'
import type { CommunityEntry, CitySector } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import EditModal, { type FieldSpec } from '../components/EditModal'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'

type Resp = { success: true; items: CommunityEntry[] }

// The always-present fields. The dynamic `sectors` multiselect is spliced in
// at render time (its options come from the admin-managed sector list). #29
// adds opening hours (4 languages) and a photo gallery.
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
  { key: 'approx_location', label: 'Map privacy',      labelKey: 'field.map_privacy',    type: 'select',   options: ['exact', 'approx'] },
  { key: 'opening_hours',        label: 'Opening Hours (EN)',     labelKey: 'field.opening_hours_en',     type: 'textarea', rows: 2, full: true },
  { key: 'opening_hours_ar',     label: 'Opening Hours (AR)',     labelKey: 'field.opening_hours_ar',     type: 'textarea', rows: 2, dir: 'rtl', full: true },
  { key: 'opening_hours_sorani', label: 'Opening Hours (Sorani)', labelKey: 'field.opening_hours_sorani', type: 'textarea', rows: 2, dir: 'rtl', full: true },
  { key: 'opening_hours_badini', label: 'Opening Hours (Badini)', labelKey: 'field.opening_hours_badini', type: 'textarea', rows: 2, dir: 'rtl', full: true },
  { key: 'description',   label: 'Description (EN)',   labelKey: 'field.description_en', type: 'textarea', rows: 3 },
  { key: 'description_ar',label: 'Description (AR)',   labelKey: 'field.description_ar', type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'gallery',       label: 'Photo Gallery',      labelKey: 'field.gallery',       type: 'gallery',  full: true },
]

export default function CityGuidePage() {
  const [resp, setResp] = useState<Resp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<CommunityEntry | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<CommunityEntry | null>(null)
  const [q, setQ] = useState('')
  const [statusFilter, setStatusFilter] = useState('') // '' = all; 'pending' | 'approved' | …
  const [refreshTick, setRefreshTick] = useState(0)
  const [sectors, setSectors] = useState<CitySector[]>([])
  const toast = useToast()
  const { t } = useI18n()

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setErr(null)
    // #30 — use the admin list so pending user submissions are visible/actionable.
    api
      .get<Resp>('/api/admin/community', {
        params: { status: statusFilter || undefined, limit: 200 },
      })
      .then((res) => { if (!cancelled) setResp(res.data) })
      .catch((e) => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [statusFilter, refreshTick])

  // #29 — the sector list is admin-managed, so fetch it to populate the
  // multiselect (values are slugs; labels resolve via the status.* namespace).
  useEffect(() => {
    let cancelled = false
    api
      .get<{ items: CitySector[] }>('/api/admin/city-sectors')
      .then((res) => { if (!cancelled) setSectors(res.data.items ?? []) })
      .catch(() => { /* non-fatal: the sectors picker just stays empty */ })
    return () => { cancelled = true }
  }, [])

  // Splice the dynamic sectors multiselect in after Category so the picker sits
  // with the other taxonomy fields.
  const fields = useMemo<FieldSpec[]>(() => {
    const sectorField: FieldSpec = {
      key: 'sectors',
      label: 'Sectors',
      labelKey: 'field.sectors',
      type: 'multiselect',
      options: sectors.map((s) => s.slug),
      full: true,
    }
    const out = [...CITY_GUIDE_FIELDS]
    const catIdx = out.findIndex((f) => f.key === 'category')
    out.splice(catIdx + 1, 0, sectorField)
    return out
  }, [sectors])

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

  // #30 — approve / reject a pending user-submitted place.
  const setStatus = useCallback(
    async (id: number, status: 'approved' | 'rejected') => {
      await api.post(`/api/admin/community/${id}/status`, { status })
      toast.success(t(status === 'approved' ? 'cityGuide.approved' : 'cityGuide.rejected'))
      setRefreshTick((n) => n + 1)
    },
    [toast, t],
  )

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const query = q.trim().toLowerCase()
  const items = (resp?.items ?? []).filter((e) =>
    !query ||
    e.name.toLowerCase().includes(query) ||
    (e.name_ar ?? '').toLowerCase().includes(query) ||
    e.category.toLowerCase().includes(query) ||
    (e.city ?? '').toLowerCase().includes(query),
  )
  const pendingCount = (resp?.items ?? []).filter((e) => e.status === 'pending').length
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
      key: 'status', header: t('col.status') ?? 'Status',
      cell: (e) => e.status === 'pending'
        ? <span className="badge" style={{ background: 'rgba(255,183,77,0.18)', color: '#ffb74d' }}>{t('cityGuide.filter_pending')}</span>
        : <span className="muted">{e.status ?? '—'}</span>,
    },
    {
      key: 'actions', header: t('common.actions'), width: '260px',
      cell: (e) => (
        <>
          {e.status === 'pending' && (
            <>
              <button className="row-edit-btn" style={{ color: '#4caf50' }} onClick={() => setStatus(e.id, 'approved')}>{t('cityGuide.approve')}</button>
              <button className="row-edit-btn" style={{ color: '#e57373' }} onClick={() => setStatus(e.id, 'rejected')}>{t('cityGuide.reject')}</button>
            </>
          )}
          <Link className="row-edit-btn" to={`/detail/community/${e.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(e)}>{t('common.edit')}</button>
          <RowDeleteButton onClick={() => setDeleting(e)} />
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
          <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} style={{ minWidth: 130 }}>
            <option value="">{t('cityGuide.filter_all')}</option>
            <option value="pending">{t('cityGuide.filter_pending')}{pendingCount ? ` (${pendingCount})` : ''}</option>
            <option value="approved">{t('cityGuide.filter_approved')}</option>
          </select>
          <Link className="row-edit-btn" to="/city-sectors">{t('citySectors.manage_link')}</Link>
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
        fields={fields}
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
