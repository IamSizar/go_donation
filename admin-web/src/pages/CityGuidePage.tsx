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
import { useI18n, type Locale } from '../lib/i18n'

type Resp = { success: true; items: CommunityEntry[] }

// Note #19 (Arabization-safe naming) — same pattern as MediaPage/MarketplacePage:
// each sector already carries its own translated name from the API, so use
// that directly rather than a shared status.* key (avoids "government" here
// colliding with the unrelated Sector Type "government" option below, which
// needs different wording — "Governmental & Sovereign Departments" vs
// "Government Sector (Public)").
function sectorName(s: CitySector, locale: Locale): string {
  const byLocale = { en: s.name_en, ar: s.name_ar, ckb: s.name_ckb, kmr: s.name_kmr }
  return byLocale[locale]?.trim() || s.name_en
}

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
  // Note #19 — "precise search filtering" by the new 5-sector taxonomy and
  // the mandatory Sector Type. Filtered client-side like the other City
  // Guide filters (the admin list is already fetched in full, limit=200).
  const [sectorFilter, setSectorFilter] = useState('')
  const [sectorTypeFilter, setSectorTypeFilter] = useState('')
  const [refreshTick, setRefreshTick] = useState(0)
  const [sectors, setSectors] = useState<CitySector[]>([])
  const toast = useToast()
  const { t, locale } = useI18n()

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

  // Note #19 — was a multiselect (an entry could carry several sector tags at
  // once). Replaced with a single-select: each place now belongs to exactly
  // one of the 5 fixed main sectors, matching the client's ask. The backend
  // column (`sectors`) stays a TEXT[] array on the wire — the Flutter app
  // reads it as an array in 4 places (filter logic, detail screen, map
  // chips), so converting the DB column to a scalar would silently break
  // sector display/filtering app-side. This page just writes a 1-element
  // array instead of letting the admin pick several — see buildSectorsPatch.
  //
  // Also splices in the new mandatory Sector Type field (government/private,
  // Note #19's second requirement) right after it.
  const fields = useMemo<FieldSpec[]>(() => {
    const sectorField: FieldSpec = {
      key: 'sector',
      label: 'Sector',
      labelKey: 'field.sector',
      type: 'select',
      options: ['', ...sectors.map((s) => s.slug)],
      optionLabels: Object.fromEntries(sectors.map((s) => [s.slug, sectorName(s, locale)])),
    }
    const sectorTypeField: FieldSpec = {
      key: 'sector_type',
      label: 'Sector Type',
      labelKey: 'field.sector_type',
      type: 'select',
      options: ['government', 'private'],
      optionLabels: {
        government: t('cityGuide.sector_type_government'),
        private: t('cityGuide.sector_type_private'),
      },
      required: true,
    }
    const out = [...CITY_GUIDE_FIELDS]
    const catIdx = out.findIndex((f) => f.key === 'category')
    out.splice(catIdx + 1, 0, sectorField, sectorTypeField)
    return out
  }, [sectors, locale, t])

  // Reads the single `sector` value EditModal produced and converts it back
  // to the `sectors` array shape the API expects (empty array when unset).
  function buildSectorsPatch(patch: Record<string, unknown>): Record<string, unknown> {
    if (!('sector' in patch)) return patch
    const { sector, ...rest } = patch
    return { ...rest, sectors: sector ? [sector] : [] }
  }

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/community/${id}`, buildSectorsPatch(patch))
      toast.success(`Place #${id} saved.`)
      setRefreshTick((n) => n + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>('/api/admin/community', buildSectorsPatch(data))
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
    (!query ||
      e.name.toLowerCase().includes(query) ||
      (e.name_ar ?? '').toLowerCase().includes(query) ||
      e.category.toLowerCase().includes(query) ||
      (e.city ?? '').toLowerCase().includes(query)) &&
    (!sectorFilter || (e.sectors ?? []).includes(sectorFilter)) &&
    (!sectorTypeFilter || e.sector_type === sectorTypeFilter),
  )
  const pendingCount = (resp?.items ?? []).filter((e) => e.status === 'pending').length
  const withCoords = items.filter(
    (e) => e.latitude !== null && e.latitude !== undefined && e.latitude !== '' &&
           e.longitude !== null && e.longitude !== undefined && e.longitude !== '',
  )

  const columns: Column<CommunityEntry>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (e) => <strong>#{e.id}</strong> },
    {
      key: 'name', header: t('cityGuide.col_place'), cell: (e) => (
        <div className="cell-stack">
          <strong>{e.name}</strong>
          {e.name_ar && <span className="muted" dir="rtl">{e.name_ar}</span>}
        </div>
      ),
    },
    { key: 'cat',  header: t('col.category'), cell: (e) => e.category },
    {
      key: 'sector', header: t('field.sector'),
      cell: (e) => {
        const slug = e.sectors?.[0]
        const s = slug ? sectors.find((x) => x.slug === slug) : undefined
        return s ? sectorName(s, locale) : <span className="muted">—</span>
      },
    },
    {
      key: 'sector_type', header: t('field.sector_type'),
      cell: (e) => e.sector_type === 'government'
        ? <span className="badge">{t('cityGuide.sector_type_government')}</span>
        : <span className="muted">{t('cityGuide.sector_type_private')}</span>,
    },
    { key: 'city', header: t('col.city'),    cell: (e) => e.city ?? <span className="muted">—</span> },
    {
      key: 'coords', header: t('cityGuide.col_coordinates'),
      cell: (e) => (e.latitude && e.longitude)
        ? <code style={{ fontSize: '11px' }}>{Number(e.latitude).toFixed(4)}, {Number(e.longitude).toFixed(4)}</code>
        : <span className="muted" style={{ color: '#e57373' }}>⚠ {t('cityGuide.no_coords')}</span>,
    },
    {
      key: 'phone', header: t('col.phone'),
      cell: (e) => e.phone
        ? <a href={`tel:${e.phone}`} style={{ color: '#4caf50' }}>{e.phone}</a>
        : <span className="muted">—</span>,
    },
    {
      key: 'link', header: t('col.link'),
      cell: (e) => e.website
        ? <a href={e.website} target="_blank" rel="noreferrer">{t('cityGuide.open_link')} ↗</a>
        : <span className="muted">—</span>,
    },
    {
      key: 'status', header: t('col.status'),
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
          {/* Note #19 — filter by the 5-sector taxonomy and Sector Type. */}
          <select value={sectorFilter} onChange={(e) => setSectorFilter(e.target.value)} style={{ minWidth: 160 }}>
            <option value="">{t('field.sector')}: {t('cityGuide.filter_all')}</option>
            {sectors.map((s) => (
              <option key={s.slug} value={s.slug}>{sectorName(s, locale)}</option>
            ))}
          </select>
          <select value={sectorTypeFilter} onChange={(e) => setSectorTypeFilter(e.target.value)} style={{ minWidth: 170 }}>
            <option value="">{t('field.sector_type')}: {t('cityGuide.filter_all')}</option>
            <option value="government">{t('cityGuide.sector_type_government')}</option>
            <option value="private">{t('cityGuide.sector_type_private')}</option>
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
        initial={
          creating
            ? {}
            : editing
              // Note #19 — surface the first (only, going forward) array
              // element as the plain `sector` value the single-select reads.
              ? { ...(editing as unknown as Record<string, unknown>), sector: editing.sectors?.[0] ?? '' }
              : {}
        }
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
