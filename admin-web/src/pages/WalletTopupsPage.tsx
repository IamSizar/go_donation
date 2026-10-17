import { useCallback, useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import Table, { type Column } from '../components/Table'
import DateCell from '../components/DateCell'
import ExportCsvButton from '../components/ExportCsvButton'
import { type CsvColumn } from '../lib/csv'
import PageHead from '../components/PageHead'
import ActionsMenu from '../components/ActionsMenu'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { fmtId } from '../lib/formatId'

// R2 #67 — a user asks for money to be added to their wallet; the request waits
// here. The wallet is untouched until staff approve it: approving credits the
// balance (and the ledger) in one step, rejecting changes nothing.
type TopUpRequest = {
  id: number
  user_id: number
  user_name: string | null
  user_phone: string | null
  amount_iqd: number
  payment_method: string
  note: string
  proof_path: string | null
  status: string
  reject_reason: string | null
  decided_at: string | null
  created_at: string
}

const CSV_COLUMNS: CsvColumn<TopUpRequest>[] = [
  { header: 'id', get: (r) => r.id },
  { header: 'user_id', get: (r) => r.user_id },
  { header: 'user_name', get: (r) => r.user_name ?? '' },
  { header: 'user_phone', get: (r) => r.user_phone ?? '' },
  { header: 'amount_iqd', get: (r) => r.amount_iqd },
  { header: 'payment_method', get: (r) => r.payment_method },
  { header: 'note', get: (r) => r.note },
  { header: 'status', get: (r) => r.status },
  { header: 'created_at', get: (r) => r.created_at },
  { header: 'decided_at', get: (r) => r.decided_at ?? '' },
]

export default function WalletTopupsPage() {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const toast = useToast()
  const [items, setItems] = useState<TopUpRequest[]>([])
  const [tick, setTick] = useState(0)
  const [loadedKey, setLoadedKey] = useState<string | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [status, setStatus] = useState('pending')
  const [busyId, setBusyId] = useState<number | null>(null)

  const requestKey = `${status}|${tick}`
  const loading = loadedKey !== requestKey

  const load = useCallback(() => {
    api
      .get<{ items: TopUpRequest[] }>('/api/admin/wallet/topup-requests', { params: { status } })
      .then((r) => { setItems(r.data.items ?? []); setErr(null) })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoadedKey(requestKey))
  }, [status, requestKey])

  useEffect(load, [load])

  const decide = async (r: TopUpRequest, approve: boolean) => {
    setBusyId(r.id)
    try {
      await api.post(`/api/admin/wallet/topup-requests/${r.id}/${approve ? 'approve' : 'reject'}`, {})
      toast.success(approve ? t('walletTopups.approved') : t('walletTopups.rejected'))
      setTick((n) => n + 1)
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyId(null)
    }
  }

  const columns: Column<TopUpRequest>[] = [
    { key: 'id', header: t('col.id'), width: '70px', cell: (r) => <strong>{fmtId(r.id, 'N')}</strong> },
    {
      key: 'user',
      header: t('col.user'),
      cell: (r) => (
        <div className="cell-stack">
          <span>{r.user_name || fmtId(r.user_id)}</span>
          <span className="muted">{r.user_phone}</span>
        </div>
      ),
    },
    {
      key: 'amount',
      header: t('col.amount'),
      align: 'right',
      cell: (r) => <strong>{r.amount_iqd.toLocaleString('en-US')} <span className="muted">IQD</span></strong>,
    },
    { key: 'method', header: t('col.payment_method'), cell: (r) => r.payment_method || <span className="muted">—</span> },
    { key: 'note', header: t('walletTopups.note'), cell: (r) => r.note || <span className="muted">—</span> },
    {
      key: 'proof',
      header: t('walletTopups.proof'),
      cell: (r) =>
        r.proof_path ? (
          <a href={r.proof_path} target="_blank" rel="noreferrer">
            <img src={r.proof_path} alt="" style={{ height: 44, borderRadius: 8 }} />
          </a>
        ) : (
          <span className="muted">—</span>
        ),
    },
    { key: 'created', header: t('col.created'), cell: (r) => <DateCell value={r.created_at} /> },
    { key: 'status', header: t('col.status'), cell: (r) => <span className="muted">{statusLabel(r.status)}</span> },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '150px',
      cell: (r) =>
        r.status !== 'pending' ? (
          <span className="muted">—</span>
        ) : (
          <ActionsMenu
            items={[
              { key: 'approve', label: t('walletTopups.approve'), disabled: busyId === r.id, onClick: () => decide(r, true) },
              { key: 'reject', label: t('walletTopups.reject'), danger: true, disabled: busyId === r.id, onClick: () => decide(r, false) },
            ]}
          />
        ),
    },
  ]

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('nav.wallet_topups')}</h1>
          <p className="muted">{t('walletTopups.subtitle')}</p>
        </div>
        <div className="row">
          <select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 'auto' }}>
            <option value="pending">{t('status.pending')}</option>
            <option value="approved">{t('status.approved')}</option>
            <option value="rejected">{t('status.rejected')}</option>
            <option value="all">{t('filter.all_statuses')}</option>
          </select>
          <ExportCsvButton
            rows={items}
            columns={CSV_COLUMNS}
            filenameBase="wallet-topup-requests"
            title={t('nav.wallet_topups')}
            module="users"
          />
        </div>
      </PageHead>
      {!loading && err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}
      {!loading && <Table rows={items} columns={columns} rowKey={(r) => r.id} />}
    </div>
  )
}
