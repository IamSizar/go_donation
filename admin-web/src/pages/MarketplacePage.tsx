import { useCallback, useEffect, useMemo, useState, useRef } from 'react'
import RowDeleteButton from '../components/RowDeleteButton'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError, assetUrl } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import type {
  AdminPageResp,
  MarketOrder,
  Product,
} from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import StatusCell from '../components/StatusCell'
import EditModal, { type FieldSpec } from '../components/EditModal'
import BulkBar from '../components/BulkBar'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel, type Locale } from '../lib/i18n'
import { useSelection } from '../lib/useSelection'
import { downloadCsv, type CsvColumn } from '../lib/csv'
import { HighlightBanner, useHighlightedRow } from '../lib/useHighlightedRow'
import { stripeForStatus } from '../lib/statusColors'
import { formatDateParts } from '../lib/dates'

const PRODUCT_CSV_COLUMNS: CsvColumn<Product>[] = [
  { header: 'id', get: (p) => p.id },
  { header: 'name', get: (p) => p.name },
  { header: 'name_ar', get: (p) => p.name_ar },
  { header: 'category', get: (p) => p.category },
  { header: 'price', get: (p) => p.price },
  { header: 'currency', get: (p) => p.currency },
  { header: 'stock_quantity', get: (p) => p.stock_quantity },
  { header: 'seller_user_id', get: (p) => p.seller_user_id },
  { header: 'status', get: (p) => p.status },
]
const ORDER_CSV_COLUMNS: CsvColumn<MarketOrder>[] = [
  { header: 'id', get: (o) => o.id },
  { header: 'product_id', get: (o) => o.product_id },
  { header: 'buyer_user_id', get: (o) => o.buyer_user_id },
  { header: 'quantity', get: (o) => o.quantity },
  { header: 'total_amount', get: (o) => o.total_amount },
  { header: 'currency', get: (o) => o.currency },
  { header: 'status', get: (o) => o.status },
  { header: 'created_at', get: (o) => o.created_at },
]

type Tab = 'products' | 'orders'

const PER_PAGE = 20

const PRODUCT_STATUSES = ['all', 'draft', 'pending', 'approved', 'rejected', 'sold_out', 'hidden']
const EDITABLE_PRODUCT_STATUSES = PRODUCT_STATUSES.filter((s) => s !== 'all')
const ORDER_STATUSES = ['all', 'pending', 'approved', 'processing', 'completed', 'cancelled']
const EDITABLE_ORDER_STATUSES = ORDER_STATUSES.filter((s) => s !== 'all')

// #28 — fixed set of product badges (must match backend marketplaceLabels).
const PRODUCT_LABELS = ['new', 'sale', 'featured', 'used', 'in_stock']

type MarketCategory = { slug: string; name_en: string; name_ar: string; name_ckb: string; name_kmr: string }

// Note #18 (Arabization) — see the identical helper + comment in
// MediaPage.tsx. Same reasoning: Marketplace's "food" category needs
// different text than Media's "food" category, so this uses the per-category
// translated name from the API instead of the shared status.* dictionary.
function categoryName(c: MarketCategory, locale: Locale): string {
  const byLocale = { en: c.name_en, ar: c.name_ar, ckb: c.name_ckb, kmr: c.name_kmr }
  return byLocale[locale]?.trim() || c.name_en
}

const PRODUCT_FIELDS: FieldSpec[] = [
  { key: 'name',                label: 'Name (EN)', labelKey: 'field.name_en',          type: 'text',     required: true },
  { key: 'name_ar',             label: 'Name (AR)', labelKey: 'field.name_ar',          type: 'text',     dir: 'rtl' },
  { key: 'name_sorani',         label: 'Name (Sorani)', labelKey: 'field.name_sorani',      type: 'text',     dir: 'rtl' },
  { key: 'name_badini',         label: 'Name (Badini)', labelKey: 'field.name_badini',      type: 'text',     dir: 'rtl' },
  { key: 'category',            label: 'Category', labelKey: 'field.category',           type: 'text' },
  { key: 'sku',                 label: 'SKU', labelKey: 'field.sku',                 type: 'text' },
  { key: 'status',              label: 'Status', labelKey: 'field.status',             type: 'select',   options: EDITABLE_PRODUCT_STATUSES },
  { key: 'price',               label: 'Price', labelKey: 'field.price',              type: 'number' },
  { key: 'currency',            label: 'Currency', labelKey: 'field.currency',           type: 'text',     placeholder: 'IQD' },
  { key: 'stock_quantity',      label: 'Stock quantity', labelKey: 'field.stock_quantity',     type: 'number' },
  { key: 'labels',              label: 'Labels', labelKey: 'field.labels',             type: 'multiselect', full: true, options: PRODUCT_LABELS },
  { key: 'specs',               label: 'Specs', labelKey: 'field.specs',              type: 'textarea', rows: 3, full: true, placeholder: 'One "Key: Value" per line' },
  { key: 'image_path',          label: 'Image', labelKey: 'field.image',              type: 'file', full: true },
  { key: 'description',         label: 'Description (EN)', labelKey: 'field.description_en',   type: 'textarea', rows: 3 },
  { key: 'description_ar',      label: 'Description (AR)', labelKey: 'field.description_ar',   type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'description_sorani',  label: 'Description (Sorani)', labelKey: 'field.description_sorani', type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'description_badini',  label: 'Description (Badini)', labelKey: 'field.description_badini', type: 'textarea', rows: 3, dir: 'rtl' },
]

// Create form adds optional seller/case linkage at the top.
const PRODUCT_CREATE_FIELDS: FieldSpec[] = [
  { key: 'seller_user_id',       label: 'Seller user ID', labelKey: 'field.seller_user_id',       type: 'number' },
  { key: 'beneficiary_case_id',  label: 'Eligible case ID', labelKey: 'field.beneficiary_case_id',  type: 'number' },
  ...PRODUCT_FIELDS,
]

const ORDER_FIELDS: FieldSpec[] = [
  { key: 'status',       label: 'Status', labelKey: 'field.status',     type: 'select',   options: EDITABLE_ORDER_STATUSES },
  { key: 'quantity',     label: 'Quantity', labelKey: 'field.quantity',   type: 'number' },
  { key: 'total_amount', label: 'Total', labelKey: 'field.total',      type: 'number' },
  { key: 'currency',     label: 'Currency', labelKey: 'field.currency',   type: 'text', placeholder: 'IQD' },
  { key: 'buyer_note',   label: 'Buyer note', labelKey: 'field.buyer_note', type: 'textarea', rows: 3 },
]

function formatAmount(s: string | number): string {
  const n = typeof s === 'number' ? s : parseFloat(s)
  if (!isFinite(n)) return String(s)
  return n.toLocaleString()
}

export default function MarketplacePage() {
  const [tab, setTab] = useState<Tab>('products')
  const { t } = useI18n()
  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.marketplace.title')}</h1>
        </div>
        <div className="tab-row">
          <button className={tab === 'products' ? '' : 'secondary'} onClick={() => setTab('products')}>
            {t('page.marketplace.tab_products')}
          </button>
          <button className={tab === 'orders' ? '' : 'secondary'} onClick={() => setTab('orders')}>
            {t('page.marketplace.tab_orders')}
          </button>
        </div>
      </div>
      {tab === 'products' ? <ProductsTab /> : <OrdersTab />}
    </div>
  )
}

function ProductsTab() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<AdminPageResp<Product> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<Product | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<Product | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t, locale } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<Product>((p) => p.id)
  const highlight = useHighlightedRow()
  const [categories, setCategories] = useState<MarketCategory[]>([]) // #28

  // #28 — load marketplace categories for the product form's category dropdown.
  useEffect(() => {
    let cancelled = false
    api
      .get<{ items: MarketCategory[] }>('/api/admin/marketplace/categories')
      .then((res) => { if (!cancelled) setCategories(res.data.items ?? []) })
      .catch(() => { if (!cancelled) setCategories([]) })
    return () => { cancelled = true }
  }, [])

  const productFields = useMemo<FieldSpec[]>(() => {
    const catField: FieldSpec = {
      key: 'category_slug', label: 'Category', labelKey: 'field.category',
      type: 'select', options: ['', ...categories.map((c) => c.slug)],
      optionLabels: Object.fromEntries(categories.map((c) => [c.slug, categoryName(c, locale)])),
    }
    const out = [...PRODUCT_FIELDS]
    const at = out.findIndex((f) => f.key === 'category')
    out.splice(at + 1, 0, catField)
    return out
  }, [categories, locale])

  const productCreateFields = useMemo<FieldSpec[]>(
    () => [PRODUCT_CREATE_FIELDS[0], PRODUCT_CREATE_FIELDS[1], ...productFields],
    [productFields],
  )

  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<AdminPageResp<Product>>('/api/admin/marketplace/products', {
        params: { page, per_page: PER_PAGE, status, q: q || undefined },
      })
      .then((res) => {
        if (!cancelled) setResp(res.data)
      })
      .catch((e) => {
        if (!cancelled && !pollSilent.current) setErr(describeError(e))
      })
      .finally(() => {
        if (!cancelled && !pollSilent.current) setLoading(false)
        pollSilent.current = false
      })
    return () => {
      cancelled = true
    }
  }, [page, status, q, refreshTick])

  // Phase 27 — live refresh marketplace products every 10s.
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 10_000)

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/marketplace/products/${id}`, patch)
      toast.success(t('toast.saved', { noun: `${t('noun.product')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(`/api/admin/marketplace/products`, data)
      toast.success(t('toast.created', { noun: `${t('noun.product')} #${res.data.id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const applyBulkStatus = useCallback(
    async (newStatus: string) => {
      const ids = [...sel.selected]
      const results = await Promise.allSettled(
        ids.map((id) => api.post(`/api/admin/marketplace/products/${id}/status`, { status: newStatus })),
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
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/marketplace/products/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/marketplace/products/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.product')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`products-${new Date().toISOString().slice(0, 10)}.csv`, rows, PRODUCT_CSV_COLUMNS)
  }

  const columns: Column<Product>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (p) => <strong>#{p.id}</strong> },
    {
      key: 'img',
      header: '',
      width: '56px',
      cell: (p) =>
        p.image_path ? (
          <img src={assetUrl(p.image_path)} alt="" className="thumb" />
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
    { key: 'cat', header: t('col.category'), cell: (p) => p.category ?? <span className="muted">—</span> },
    {
      key: 'price',
      header: t('col.price'),
      align: 'right',
      cell: (p) => (
        <strong>
          {formatAmount(p.price)} <span className="muted">{p.currency}</span>
        </strong>
      ),
    },
    {
      key: 'stock',
      header: t('col.stock'),
      align: 'right',
      cell: (p) => p.stock_quantity ?? <span className="muted">—</span>,
    },
    {
      key: 'seller',
      header: t('col.seller'),
      cell: (p) =>
        p.seller_user_id ? `user #${p.seller_user_id}` : <span className="muted">—</span>,
    },
    {
      key: 'status',
      header: t('col.status'),
      cell: (p) => (
        <StatusCell
          value={p.status}
          allowed={EDITABLE_PRODUCT_STATUSES}
          onSave={(next) => api.post(`/api/admin/marketplace/products/${p.id}/status`, { status: next })}
          label={`Product #${p.id}`}
        />
      ),
    },
    {
      key: 'actions', header: t('common.actions'), width: '170px',
      cell: (p) => (
        <>
          <Link className="row-edit-btn" to={`/detail/products/${p.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(p)}>{t('common.edit')}</button>
          <RowDeleteButton onClick={() => setDeleting(p)} />
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <p className="muted">{resp ? `${resp.total_items} total products` : 'Loading…'}</p>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1); sel.clear() }}
            placeholder={t('page.marketplace.products_search_placeholder')}
            style={{ width: '200px' }}
          />
          <select value={status} onChange={(e) => { setStatus(e.target.value); setPage(1); sel.clear() }} style={{ width: 'auto' }}>
            {PRODUCT_STATUSES.map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}
          </select>
          <ExportCsvButton onExport={exportCsv} />
          <button onClick={() => setCreating(true)}>{t('page.marketplace.new_product')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <HighlightBanner kind={t('noun.product')} />
      <Table<Product>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(p) => p.id}
        loading={loading}
        empty={t('empty.products')}
        selectable={sel.forRows(resp?.items ?? [])}
        rowProps={(p) => ({
          className: [
            highlight.isHighlighted(p.id) ? 'is-highlighted' : '',
            stripeForStatus(p.status),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(p.id),
        })}
      />
      <Pagination page={page} totalPages={resp?.total_pages ?? 1} onPageChange={setPage} disabled={loading} />
      <BulkBar
        count={sel.count}
        allowed={EDITABLE_PRODUCT_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun="products"
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.product'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body', { name: deleting.name }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.product') }) : editing ? t('common.modal_edit', { noun: t('noun.product'), id: editing.id }) : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={creating ? productCreateFields : productFields}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
    </div>
  )
}

function OrdersTab() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<AdminPageResp<MarketOrder> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<MarketOrder | null>(null)
  const [deleting, setDeleting] = useState<MarketOrder | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t, locale } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<MarketOrder>((o) => o.id)
  const highlight = useHighlightedRow()
  // Note #18 (Arabization) — orders show the product's category slug; needs
  // the same per-category translated name as the product form's dropdown
  // (see categoryName() + comment above), not the shared status.* dict.
  const [categories, setCategories] = useState<MarketCategory[]>([])

  useEffect(() => {
    let cancelled = false
    api
      .get<{ items: MarketCategory[] }>('/api/admin/marketplace/categories')
      .then((res) => { if (!cancelled) setCategories(res.data.items ?? []) })
      .catch(() => { if (!cancelled) setCategories([]) })
    return () => { cancelled = true }
  }, [])

  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<AdminPageResp<MarketOrder>>('/api/admin/marketplace/orders', {
        params: { page, per_page: PER_PAGE, status, q: q || undefined },
      })
      .then((res) => {
        if (!cancelled) setResp(res.data)
      })
      .catch((e) => {
        if (!cancelled && !pollSilent.current) setErr(describeError(e))
      })
      .finally(() => {
        if (!cancelled && !pollSilent.current) setLoading(false)
        pollSilent.current = false
      })
    return () => {
      cancelled = true
    }
  }, [page, status, q, refreshTick])

  // Phase 27 — live refresh marketplace orders every 5s (order status
  // transitions are more time-sensitive than product catalog edits).
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 5_000)

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/marketplace/orders/${id}`, patch)
      toast.success(t('toast.saved', { noun: `${t('noun.order')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const applyBulkStatus = useCallback(
    async (newStatus: string) => {
      const ids = [...sel.selected]
      const results = await Promise.allSettled(
        ids.map((id) => api.post(`/api/admin/marketplace/orders/${id}/status`, { status: newStatus })),
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
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/marketplace/orders/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/marketplace/orders/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.order')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`orders-${new Date().toISOString().slice(0, 10)}.csv`, rows, ORDER_CSV_COLUMNS)
  }

  const columns: Column<MarketOrder>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (o) => <strong>T{o.id}</strong> },
    {
      key: 'product',
      header: t('col.product'),
      cell: (o) => (
        <div className="cell-stack">
          <strong>{o.name ?? `Product #${o.product_id}`}</strong>
          {o.category && (
            <span className="muted">
              {categoryName(categories.find((c) => c.slug === o.category) ?? { slug: o.category, name_en: o.category, name_ar: '', name_ckb: '', name_kmr: '' }, locale)}
            </span>
          )}
        </div>
      ),
    },
    {
      key: 'buyer',
      header: t('col.buyer'),
      cell: (o) =>
        o.buyer_user_id ? `user #${o.buyer_user_id}` : <span className="muted">—</span>,
    },
    { key: 'qty', header: t('col.qty'), align: 'right', cell: (o) => o.quantity },
    {
      key: 'total',
      header: t('col.total'),
      align: 'right',
      cell: (o) => (
        <strong>
          {formatAmount(o.total_amount)} <span className="muted">{o.currency}</span>
        </strong>
      ),
    },
    {
      key: 'status',
      header: t('col.status'),
      cell: (o) => (
        <StatusCell
          value={o.status}
          allowed={EDITABLE_ORDER_STATUSES}
          onSave={(next) => api.post(`/api/admin/marketplace/orders/${o.id}/status`, { status: next })}
          label={`Order #${o.id}`}
        />
      ),
    },
    {
      key: 'created',
      header: t('col.placed'),
      cell: (o) => {
        if (!o.created_at) return <span className="muted">—</span>
        const { date, time } = formatDateParts(o.created_at)
        return (
          <div className="cell-stack">
            <span>{date}</span>
            <span className="muted">{time}</span>
          </div>
        )
      },
    },
    {
      key: 'actions', header: t('common.actions'), width: '170px',
      cell: (o) => (
        <>
          <Link className="row-edit-btn" to={`/detail/orders/${o.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(o)}>{t('common.edit')}</button>
          <RowDeleteButton onClick={() => setDeleting(o)} />
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <p className="muted">{resp ? `${resp.total_items} total orders` : 'Loading…'}</p>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1); sel.clear() }}
            placeholder={t('page.marketplace.orders_search_placeholder')}
            style={{ width: '200px' }}
          />
          <select value={status} onChange={(e) => { setStatus(e.target.value); setPage(1); sel.clear() }} style={{ width: 'auto' }}>
            {ORDER_STATUSES.map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}
          </select>
          <ExportCsvButton onExport={exportCsv} />
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <HighlightBanner kind={t('noun.order')} />
      <Table<MarketOrder>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(o) => o.id}
        loading={loading}
        empty={t('empty.orders')}
        selectable={sel.forRows(resp?.items ?? [])}
        rowProps={(o) => ({
          className: [
            highlight.isHighlighted(o.id) ? 'is-highlighted' : '',
            stripeForStatus(o.status),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(o.id),
        })}
      />
      <Pagination page={page} totalPages={resp?.total_pages ?? 1} onPageChange={setPage} disabled={loading} />
      <BulkBar
        count={sel.count}
        allowed={EDITABLE_ORDER_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun="orders"
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.order'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body_noun', { noun: t('noun.order') }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={editing !== null}
        title={editing ? `Edit order #${editing.id}` : ''}
        initial={editing as unknown as Record<string, unknown> ?? {}}
        fields={ORDER_FIELDS}
        onSave={(patch) => handleSave(editing!.id, patch)}
        onClose={() => setEditing(null)}
      />
    </div>
  )
}
