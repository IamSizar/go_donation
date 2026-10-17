// ReceiptsPage — digital aid-delivery receipts (#50). Admin records a delivery
// (items + proof photos + recipient); the recipient views it in the app.
// GET/POST /api/admin/aid-receipts.
import { useCallback, useEffect, useMemo, useState } from 'react'
import { api, describeError } from '../lib/api'
import { fetchAllUsers } from '../lib/fetchAllUsers'
import Table, { type Column } from '../components/Table'
import ExportCsvButton from '../components/ExportCsvButton'
import DateCell from '../components/DateCell'
import { type CsvColumn } from '../lib/csv'
import EditModal, { type FieldSpec } from '../components/EditModal'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'
import PageHead from '../components/PageHead'

type Receipt = {
  id: number
  receipt_code: string
  recipient_user_id: number | null
  recipient_name: string | null
  items: string | null
  delivered_at: string | null
  delivered_by: string | null
  photos: string[] | null
  notes: string | null
  /** When the receipt was recorded (ISO); delivered_at is the delivery day only. */
  created_at?: string | null
}

const RECEIPT_CSV_COLUMNS: CsvColumn<Receipt>[] = [
  { header: 'receipt_code', get: (r) => r.receipt_code },
  { header: 'recipient_name', get: (r) => r.recipient_name ?? '' },
  { header: 'recipient_user_id', get: (r) => r.recipient_user_id ?? '' },
  { header: 'items', get: (r) => r.items ?? '' },
  { header: 'delivered_at', get: (r) => r.delivered_at ?? '' },
  { header: 'delivered_by', get: (r) => r.delivered_by ?? '' },
  { header: 'photos', get: (r) => r.photos?.length ?? 0 },
  { header: 'notes', get: (r) => r.notes ?? '' },
  { header: 'created_at', get: (r) => r.created_at ?? '' },
]

// Minimal shape of a user from /api/admin/users, for the recipient/deliverer
// dropdowns.
type AdminUser = {
  user_id: number
  phone: string
  profile?: { full_name?: string | null } | null
}

export default function ReceiptsPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Receipt[]>([])
  const [users, setUsers] = useState<AdminUser[]>([])
  // Which reload tick last came back. `loading` is derived from it below
  // rather than set at the top of the fetch effect.
  const [loadedTick, setLoadedTick] = useState(-1)
  const [err, setErr] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [tick, setTick] = useState(0)

  const loading = loadedTick !== tick

  useEffect(() => {
    api
      .get<{ items: Receipt[] }>('/api/admin/aid-receipts')
      .then((res) => { setItems(res.data.items ?? []); setErr(null) })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoadedTick(tick))
  }, [tick])

  // Load users once for the recipient / delivered-by pickers.
  useEffect(() => {
    // Every account, page by page — a per_page of 200 is not honoured and
    // used to offer only the newest 20 (lib/fetchAllUsers.ts).
    fetchAllUsers()
      .then((all) => setUsers(all as unknown as AdminUser[]))
      .catch(() => {})
  }, [])

  // Build the create-form fields, with dropdowns populated from the users list
  // so staff select a recipient / deliverer instead of typing raw values, and a
  // real date picker for "Delivered on" (a free-text date caused DB errors).
  const FIELDS: FieldSpec[] = useMemo(() => {
    const userName = (u: AdminUser) => (u.profile?.full_name || `#${u.user_id}`)
    const recipientOptions = ['', ...users.map((u) => String(u.user_id))]
    const recipientLabels: Record<string, string> = { '': '—' }
    users.forEach((u) => { recipientLabels[String(u.user_id)] = `${userName(u)} · ${u.phone}` })
    const deliveredByOptions = ['', ...Array.from(new Set(users.map(userName)))]
    const deliveredByLabels: Record<string, string> = { '': '—' }
    deliveredByOptions.forEach((n) => { if (n) deliveredByLabels[n] = n })

    return [
      { key: 'recipient_user_id', label: 'Recipient',       labelKey: 'receipts.recipient_id',   type: 'select', options: recipientOptions, optionLabels: recipientLabels },
      { key: 'recipient_name',    label: 'Recipient name (optional)', labelKey: 'receipts.recipient_name', type: 'text' },
      { key: 'items',             label: 'Items delivered', labelKey: 'receipts.items',           type: 'textarea', rows: 2 },
      { key: 'delivered_at',      label: 'Delivered on',    labelKey: 'receipts.delivered_at',    type: 'date' },
      { key: 'delivered_by',      label: 'Delivered by',    labelKey: 'receipts.delivered_by',    type: 'select', options: deliveredByOptions, optionLabels: deliveredByLabels },
      { key: 'photos',            label: 'Photos',          labelKey: 'receipts.photos',          type: 'gallery', full: true },
      { key: 'notes',             label: 'Notes',           labelKey: 'receipts.notes',           type: 'textarea', rows: 2 },
    ]
  }, [users])

  const handleCreate = useCallback(async (data: Record<string, unknown>) => {
    // recipient_user_id comes from a <select> as a string; the backend wants a
    // number (or null when blank).
    const rid = data.recipient_user_id
    const payload = {
      ...data,
      recipient_user_id: rid ? Number(rid) : null,
    }
    const res = await api.post<{ receipt_code: string }>('/api/admin/aid-receipts', payload)
    toast.success(`${t('receipts.created')} ${res.data.receipt_code}`)
    setTick((n) => n + 1)
  }, [toast, t])

  const columns: Column<Receipt>[] = [
    { key: 'code', header: t('receipts.code'), cell: (r) => <code>{r.receipt_code}</code> },
    { key: 'recipient', header: t('receipts.recipient_name'), cell: (r) => r.recipient_name || (r.recipient_user_id ? `#${r.recipient_user_id}` : '—') },
    { key: 'items', header: t('receipts.items'), cell: (r) => r.items || '—' },
    { key: 'delivered_at', header: t('receipts.delivered_at'), cell: (r) => r.delivered_at || '—' },
    { key: 'photos', header: t('receipts.photos'), cell: (r) => (r.photos?.length ?? 0).toString() },
    { key: 'created', header: t('col.created'), cell: (r) => <DateCell value={r.created_at} /> },
  ]

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('receipts.title')}</h1>
          <p className="muted">{t('receipts.subtitle')}</p>
        </div>
        <div className="row">
          <ExportCsvButton
            rows={items}
            columns={RECEIPT_CSV_COLUMNS}
            filenameBase="aid-receipts"
            title={t('receipts.title')}
            module="receipts"
          />
          <button onClick={() => setCreating(true)}>{t('receipts.new')}</button>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}

      <Table<Receipt> rows={items} columns={columns} rowKey={(r) => r.id} loading={loading} empty={t('receipts.empty')} />

      <EditModal
        open={creating}
        mode="create"
        title={t('receipts.new')}
        initial={{}}
        fields={FIELDS}
        onSave={handleCreate}
        onClose={() => setCreating(false)}
      />
    </div>
  )
}
