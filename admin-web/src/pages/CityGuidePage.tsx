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
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import LocalizedCell from '../components/LocalizedCell'
import DateCell from '../components/DateCell'
import ExportCsvButton from '../components/ExportCsvButton'
import BulkBar from '../components/BulkBar'
import { useSelection } from '../lib/useSelection'
import { type CsvColumn } from '../lib/csv'
import { hasValidCoords } from '../lib/cityCoords'
import { Link } from 'react-router-dom'
import { api, describeError } from '../lib/api'
import type { CommunityEntry, CitySector } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import EditModal, { type FieldSpec } from '../components/EditModal'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel, type Locale } from '../lib/i18n'
import PageHead, { PageActions } from '../components/PageHead'
import { fmtId } from '../lib/formatId'
import RowActionsMenu from '../components/RowActionsMenu'

type Resp = { success: true; items: CommunityEntry[] }

const CITY_GUIDE_CSV_COLUMNS: CsvColumn<CommunityEntry>[] = [
  { header: 'id', get: (e) => e.id },
  { header: 'name', get: (e) => e.name },
  { header: 'name_ar', get: (e) => e.name_ar },
  { header: 'category', get: (e) => e.category },
  { header: 'sector', get: (e) => e.sectors?.[0] ?? '' },
  { header: 'sector_type', get: (e) => e.sector_type },
  { header: 'city', get: (e) => e.city },
  { header: 'address', get: (e) => e.address },
  { header: 'latitude', get: (e) => e.latitude },
  { header: 'longitude', get: (e) => e.longitude },
  { header: 'phone', get: (e) => e.phone },
  { header: 'website', get: (e) => e.website },
  { header: 'status', get: (e) => e.status },
  { header: 'created_at', get: (e) => e.created_at ?? '' },
]

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
  { key: 'phone',         label: 'Phone Number',       labelKey: 'field.phone',          type: 'text',     phone: 'contact' },
  // E6 — "كيفية اضافة رابط": the client could not tell what belonged in this
  // box. It was the only link-ish field on the form with no example, while
  // `social_links` and `hours` below it both show one, so it read as a
  // free-text note rather than a URL. A bare URL sample carries no English to
  // translate (see EditModal's `placeholderKey` note), so it is the same
  // placeholder in all four locales.
  { key: 'website',       label: 'Link / Website',     labelKey: 'field.website',        type: 'text',
    placeholder: 'https://example.com' },
  { key: 'latitude',      label: 'Latitude',           labelKey: 'field.latitude',       type: 'text',     required: true },
  { key: 'longitude',     label: 'Longitude',          labelKey: 'field.longitude',      type: 'text',     required: true },
  { key: 'approx_location', label: 'Map privacy',      labelKey: 'field.map_privacy',    type: 'select',   options: ['exact', 'approx'] },
  { key: 'opening_hours',        label: 'Opening Hours (EN)',     labelKey: 'field.opening_hours_en',     type: 'textarea', rows: 2, full: true },
  { key: 'opening_hours_ar',     label: 'Opening Hours (AR)',     labelKey: 'field.opening_hours_ar',     type: 'textarea', rows: 2, dir: 'rtl', full: true },
  { key: 'opening_hours_sorani', label: 'Opening Hours (Sorani)', labelKey: 'field.opening_hours_sorani', type: 'textarea', rows: 2, dir: 'rtl', full: true },
  { key: 'opening_hours_badini', label: 'Opening Hours (Badini)', labelKey: 'field.opening_hours_badini', type: 'textarea', rows: 2, dir: 'rtl', full: true },
  { key: 'description',   label: 'Description (EN)',   labelKey: 'field.description_en', type: 'textarea', rows: 3 },
  { key: 'description_ar',label: 'Description (AR)',   labelKey: 'field.description_ar', type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'social_links',  label: 'Social links',       labelKey: 'field.social_links',  type: 'textarea', rows: 2, full: true,
    placeholder: 'facebook.com/... · instagram.com/...' },
  // Machine-readable hours behind the Open Now badge. The four opening_hours
  // fields above stay as the human-readable text; this only drives the badge,
  // so leaving it empty keeps today's behaviour.
  { key: 'hours',         label: 'Hours (JSON)',       labelKey: 'field.hours_json',    type: 'textarea', rows: 3, full: true,
    placeholder: '{"mon":[["09:00","17:00"]],"fri":[]}' },
  { key: 'gallery',       label: 'Photo Gallery',      labelKey: 'field.gallery',       type: 'gallery',  full: true },
]

export default function CityGuidePage() {
  const [resp, setResp] = useState<Resp | null>(null)
  // Which request last came back. `loading` is derived from it below rather
  // than set at the top of the fetch effect, which costs a second render and
  // is what `react-hooks/set-state-in-effect` objects to.
  const [loadedKey, setLoadedKey] = useState<string | null>(null)
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
  // Set by clicking the missing-coordinates banner: keep only the places that
  // would not show on the app map.
  const [onlyMissingCoords, setOnlyMissingCoords] = useState(false)
  const tableRef = useRef<HTMLDivElement | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  const [sectors, setSectors] = useState<CitySector[]>([])
  const toast = useToast()
  const { t, locale } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<CommunityEntry>((e) => e.id)

  // Every dependency of the fetch effect below, so the page reads as loading
  // from the render that changes either of them.
  const requestKey = `${statusFilter}|${refreshTick}`
  const loading = loadedKey !== requestKey

  useEffect(() => {
    let cancelled = false
    // #30 — use the admin list so pending user submissions are visible/actionable.
    api
      .get<Resp>('/api/admin/community', {
        params: { status: statusFilter || undefined, limit: 200 },
      })
      .then((res) => { if (!cancelled) { setResp(res.data); setErr(null) } })
      .catch((e) => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoadedKey(requestKey) })
    return () => { cancelled = true }
  }, [statusFilter, refreshTick, requestKey])

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
      // These three toasts were the only hardcoded English strings left in
      // src/: `Place #12 saved.` appeared in Arabic, Sorani and Badini alike.
      // Every sibling page (PartnersPage.tsx:103-153 is the closest twin) says
      // it as t('toast.saved', { noun: `${t('noun.x')} #id` }), and both keys
      // this needs — toast.saved/created/deleted and noun.place — already exist
      // in all four locales, so nothing new had to be written.
      toast.success(t('toast.saved', { noun: `${t('noun.place')} #${id}` }))
      setRefreshTick((n) => n + 1)
    },
    [toast, t],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>('/api/admin/community', buildSectorsPatch(data))
      toast.success(t('toast.created', { noun: `${t('noun.place')} #${res.data.id}` }))
      setRefreshTick((n) => n + 1)
    },
    [toast, t],
  )

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/community/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.place')} #${id}` }))
      setDeleting(null)
      setRefreshTick((n) => n + 1)
    },
    [toast, t],
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

  const applyBulkDelete = useCallback(async () => {
    const ids = [...sel.selected]
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/community/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((n) => n + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const query = q.trim().toLowerCase()
  const matching = (resp?.items ?? []).filter((e) =>
    (!query ||
      e.name.toLowerCase().includes(query) ||
      (e.name_ar ?? '').toLowerCase().includes(query) ||
      e.category.toLowerCase().includes(query) ||
      (e.city ?? '').toLowerCase().includes(query)) &&
    (!sectorFilter || (e.sectors ?? []).includes(sectorFilter)) &&
    (!sectorTypeFilter || e.sector_type === sectorTypeFilter),
  )
  const withCoords = matching.filter(hasValidCoords)
  const missingCount = matching.length - withCoords.length
  // The "show only missing" filter is dropped by itself once nothing is missing
  // (e.g. the last offending place was just fixed), so the table never sits
  // empty behind a banner that is no longer there.
  const showingMissing = onlyMissingCoords && missingCount > 0
  const items = showingMissing ? matching.filter((e) => !hasValidCoords(e)) : matching
  const pendingCount = (resp?.items ?? []).filter((e) => e.status === 'pending').length

  const showMissing = () => {
    setOnlyMissingCoords(true)
    sel.clear()
    // Wait a frame so the filtered table is what scrolls into view.
    requestAnimationFrame(() => tableRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }))
  }
  const showAll = () => { setOnlyMissingCoords(false); sel.clear() }

  const columns: Column<CommunityEntry>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (e) => <strong>{fmtId(e.id, 'W')}</strong> },
    {
      key: 'name', header: t('cityGuide.col_place'), cell: (e) => (
<LocalizedCell row={e} field="name" locale={locale} dir="rtl" />
      ),
    },
    // Legacy free-text category slug from the backend — printed raw it showed
    // e.g. "food_pantry". statusLabel resolves it, or degrades to the value.
    { key: 'cat',  header: t('col.category'), cell: (e) => e.category ? statusLabel(e.category) : <span className="muted">—</span> },
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
      cell: (e) => hasValidCoords(e)
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
      key: 'created',
      header: t('col.created'),
      cell: (e) => <DateCell value={e.created_at} />,
    },
    {
      key: 'status', header: t('col.status'),
      // Only 'pending' was special-cased; every other status (approved,
      // rejected, …) fell through and rendered as a raw English token.
      cell: (e) => e.status === 'pending'
        ? <span className="badge" style={{ background: 'rgba(255,183,77,0.18)', color: '#ffb74d' }}>{t('cityGuide.filter_pending')}</span>
        : <span className="muted">{e.status ? statusLabel(e.status) : '—'}</span>,
    },
    {
      key: 'actions', header: t('common.actions'), width: '260px',
      cell: (e) => (
        <RowActionsMenu
          viewHref={`/detail/community/${e.id}`}
          onEdit={() => setEditing(e)}
          onDelete={() => setDeleting(e)}
          // Approve / Reject only apply while the entry is pending; as menu
          // entries they're simply absent otherwise.
          extra={
            e.status === 'pending'
              ? [
                  { key: 'approve', label: t('cityGuide.approve'), onClick: () => setStatus(e.id, 'approved') },
                  { key: 'reject', label: t('cityGuide.reject'), onClick: () => setStatus(e.id, 'rejected'), danger: true },
                ]
              : []
          }
        />
      ),
    },
  ]

  return (
    <div className="stack">
      {/* ── header ─────────────────────────────────────────────────────── */}
      <PageHead>
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
            onChange={(e) => { setQ(e.target.value); sel.clear() }}
            placeholder={t('common.city_search')}
            style={{ width: '200px' }}
          />
          <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); sel.clear() }} style={{ width: 130 }}>
            <option value="">{t('cityGuide.filter_all')}</option>
            <option value="pending">{t('cityGuide.filter_pending')}{pendingCount ? ` (${pendingCount})` : ''}</option>
            <option value="approved">{t('cityGuide.filter_approved')}</option>
          </select>
          {/* Note #19 — filter by the 5-sector taxonomy and Sector Type. */}
          <select value={sectorFilter} onChange={(e) => { setSectorFilter(e.target.value); sel.clear() }} style={{ width: 160 }}>
            <option value="">{t('field.sector')}: {t('cityGuide.filter_all')}</option>
            {sectors.map((s) => (
              <option key={s.slug} value={s.slug}>{sectorName(s, locale)}</option>
            ))}
          </select>
          <select
            value={sectorTypeFilter}
            onChange={(e) => { setSectorTypeFilter(e.target.value); sel.clear() }}
            style={{ width: 160 }}
          >
            <option value="">{t('field.sector_type')}: {t('cityGuide.filter_all')}</option>
            <option value="government">{t('cityGuide.sector_type_government')}</option>
            <option value="private">{t('cityGuide.sector_type_private')}</option>
          </select>
          <ExportCsvButton
            rows={items}
            columns={CITY_GUIDE_CSV_COLUMNS}
            filenameBase="city-guide"
            title={t('nav.city_guide')}
            module="community"
          />
          <Link className="row-edit-btn" to="/city-sectors">{t('citySectors.manage_link')}</Link>
        </div>
      </PageHead>

      {/* Primary action sits next to Save rather than at the end of the
          filter run, so the two buttons that change something are together. */}
      <PageActions>
        <button onClick={() => setCreating(true)}>{t('common.city_add_place')}</button>
      </PageActions>


      {/* ── coord warning ───────────────────────────────────────────────── */}
      {!loading && missingCount > 0 && (
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '12px',
            flexWrap: 'wrap',
            padding: '10px 16px',
            background: 'rgba(229,115,115,0.1)',
            border: '1px solid rgba(229,115,115,0.3)',
            borderRadius: '8px',
            fontSize: '13px',
            color: '#e57373',
          }}
        >
          {/* A real button: keyboard-reachable, announces what it does. */}
          <button
            type="button"
            className="link-btn"
            onClick={showMissing}
            aria-pressed={showingMissing}
            title={t('cityGuide.missing_coords_show')}
            style={{
              all: 'unset',
              cursor: 'pointer',
              color: 'inherit',
              textDecoration: 'underline',
              textUnderlineOffset: '3px',
              flex: '1 1 auto',
            }}
          >
            ⚠ {t('cityGuide.missing_coords_warning', { n: missingCount })}
          </button>
          {showingMissing && (
            <>
              <span className="muted">{t('cityGuide.missing_coords_showing')}</span>
              <button type="button" className="secondary" onClick={showAll}>
                {t('cityGuide.missing_coords_show_all')}
              </button>
            </>
          )}
        </div>
      )}

      {/* Hidden while a newer request is in flight, which is what clearing the
          error at the top of the fetch effect used to achieve. */}
      {!loading && err && <div className="error-box">{err}</div>}

      <div ref={tableRef} style={{ scrollMarginTop: 'var(--space-4)' }}>
        <Table<CommunityEntry>
          rows={items}
          columns={columns}
          rowKey={(e) => e.id}
          loading={loading}
          empty={t('common.city_empty')}
          selectable={sel.forRows(items)}
        />
      </div>
      <BulkBar count={sel.count} onDelete={applyBulkDelete} onClear={sel.clear} noun={t('noun.place')} />

      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.place') }) : editing ? t('common.modal_edit', { noun: t('noun.place'), id: editing.id }) : ''}
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
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.place'), id: deleting.id }) : ''}
        message={deleting ? t('cityGuide.confirm_delete_body', { name: deleting.name }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}
