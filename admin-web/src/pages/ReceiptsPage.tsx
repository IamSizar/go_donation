// ReceiptsPage — digital aid-delivery receipts (#50). Admin records a delivery
// (items + proof photos + recipient); the recipient views it in the app.
// GET/POST /api/admin/aid-receipts.
import { useCallback, useEffect, useMemo, useState } from 'react'
import { api, describeError } from '../lib/api'
import Table, { type Column } from '../components/Table'
import EditModal, { type FieldSpec } from '../components/EditModal'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'

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
}

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
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [tick, setTick] = useState(0)

  useEffect(() => {
    setLoading(true)
    api
      .get<{ items: Receipt[] }>('/api/admin/aid-receipts')
      .then((res) => { setItems(res.data.items ?? []); setErr(null) })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }, [tick])

  // Load users once for the recipient / delivered-by pickers.
  useEffect(() => {
    api
      .get<{ data: AdminUser[] }>('/api/admin/users?page=1&per_page=200')
      .then((res) => setUsers(res.data.data ?? []))
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
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('receipts.title')}</h1>
          <p className="muted">{t('receipts.subtitle')}</p>
        </div>
        <button onClick={() => setCreating(true)}>{t('receipts.new')}</button>
      </div>

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
