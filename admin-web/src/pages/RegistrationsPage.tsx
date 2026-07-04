import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError } from '../lib/api'
import type { AdminPageResp, AdminRegistration } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'
import { usePendingCounts } from '../lib/pendingCounts'
import { useLivePoll } from '../lib/useLivePoll'
import { formatPhone } from '../lib/phone'
import { downloadCsv, type CsvColumn } from '../lib/csv'

const PER_PAGE = 20
const STATUSES = ['pending', 'rejected', 'all'] as const
type StatusFilter = (typeof STATUSES)[number]

function roleKey(roleId: number): string {
  switch (roleId) {
    case 1:
      return 'registrations.role_donor'
    case 2:
      return 'registrations.role_beneficiary'
    case 3:
      return 'registrations.role_volunteer'
    default:
      return ''
  }
}

const REGISTRATION_CSV_COLUMNS: CsvColumn<AdminRegistration>[] = [
  { header: 'user_id', get: (r) => r.user_id },
  { header: 'full_name', get: (r) => r.full_name },
  { header: 'phone', get: (r) => r.phone },
  { header: 'role_id', get: (r) => r.role_id },
  { header: 'registration_status', get: (r) => r.registration_status },
  { header: 'date_of_birth', get: (r) => r.date_of_birth },
  { header: 'address', get: (r) => r.address },
  { header: 'submitted_at', get: (r) => r.submitted_at },
  { header: 'reject_reason', get: (r) => r.reject_reason },
  { header: 'created_at', get: (r) => r.created_at },
]

export default function RegistrationsPage() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState<StatusFilter>('pending')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<AdminPageResp<AdminRegistration> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  const [busyId, setBusyId] = useState<number | null>(null)
  const [rejecting, setRejecting] = useState<AdminRegistration | null>(null)
  const [reason, setReason] = useState('')
  const toast = useToast()
  const { t } = useI18n()
  const pending = usePendingCounts()

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setErr(null)
    api
      .get<AdminPageResp<AdminRegistration>>('/api/admin/registrations', {
        params: { page, per_page: PER_PAGE, status, q: q || undefined },
      })
      .then((r) => {
        if (!cancelled) setResp(r.data)
      })
      .catch((e) => {
        if (!cancelled) setErr(describeError(e))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [page, status, q, refreshTick])

  // Keep the queue fresh while the admin watches it.
  useLivePoll(() => setRefreshTick((n) => n + 1), 10_000)

  const refreshAll = useCallback(() => {
    setRefreshTick((n) => n + 1)
    pending.refresh() // update the sidebar badge immediately
  }, [pending])

  const approve = useCallback(
    async (r: AdminRegistration) => {
      setBusyId(r.user_id)
      try {
        await api.post(`/api/admin/registrations/${r.user_id}/approve`)
        toast.success(
          t('registrations.approved_toast', {
            name: r.full_name || `#${r.user_id}`,
          }),
        )
        refreshAll()
      } catch (e) {
        toast.error(describeError(e))
      } finally {
        setBusyId(null)
      }
    },
    [toast, t, refreshAll],
  )

  const doReject = useCallback(async () => {
    if (!rejecting) return
    const r = rejecting
    // Global notice #k — a rejection reason is mandatory.
    if (!reason.trim()) {
      toast.error(t('registrations.reason_required'))
      return
    }
    setBusyId(r.user_id)
    try {
      await api.post(`/api/admin/registrations/${r.user_id}/reject`, {
        reason: reason.trim(),
      })
      toast.success(
        t('registrations.rejected_toast', {
          name: r.full_name || `#${r.user_id}`,
        }),
      )
      setRejecting(null)
      setReason('')
      refreshAll()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyId(null)
    }
  }, [rejecting, reason, toast, t, refreshAll])

  const columns: Column<AdminRegistration>[] = [
    {
      key: 'applicant',
      header: t('registrations.col_applicant'),
      cell: (r) => (
        <div className="cell-stack">
          <strong>{r.full_name || `user #${r.user_id}`}</strong>
          <span className="muted">{formatPhone(r.phone)}</span>
        </div>
      ),
    },
    {
      key: 'born',
      header: t('registrations.col_born'),
      cell: (r) => r.date_of_birth || <span className="muted">—</span>,
    },
    {
      key: 'address',
      header: t('registrations.col_address'),
      cell: (r) => r.address || <span className="muted">—</span>,
    },
    {
      key: 'role',
      header: t('registrations.col_role'),
      cell: (r) =>
        roleKey(r.role_id) ? (
          <span className="role-chip">{t(roleKey(r.role_id))}</span>
        ) : (
          <span className="muted">—</span>
        ),
    },
    {
      key: 'submitted',
      header: t('registrations.col_submitted'),
      cell: (r) => (
        <span className="muted">{r.submitted_at?.slice(0, 10) ?? '—'}</span>
      ),
    },
    {
      key: 'status',
      header: t('common.status'),
      cell: (r) => (
        <div className="cell-stack">
          <span
            className="status-tag"
            style={{
              color: r.registration_status === 'rejected' ? '#b42318' : '#92610a',
              background:
                r.registration_status === 'rejected' ? '#fee4e2' : '#fef0c7',
              padding: '2px 9px',
              borderRadius: 999,
              fontSize: 12,
              fontWeight: 700,
              alignSelf: 'flex-start',
            }}
          >
            {t(`registrations.status_${r.registration_status}`)}
          </span>
          {r.registration_status === 'rejected' && r.reject_reason && (
            <span className="muted" style={{ fontSize: 11, maxWidth: 240, whiteSpace: 'normal' }}>
              {r.reject_reason}
            </span>
          )}
        </div>
      ),
    },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '280px',
      cell: (r) => (
        <>
          <Link className="row-edit-btn" to={`/detail/users/${r.user_id}`}>{t('common.view')}</Link>
          <button
            className="row-edit-btn"
            disabled={busyId === r.user_id}
            onClick={() => approve(r)}
          >
            {t('registrations.accept')}
          </button>
          <button
            className="row-delete-btn"
            disabled={busyId === r.user_id}
            onClick={() => {
              setRejecting(r)
              setReason(r.reject_reason ?? '')
            }}
          >
            {t('registrations.reject')}
          </button>
        </>
      ),
    },
  ]

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`registrations-${new Date().toISOString().slice(0, 10)}.csv`, rows, REGISTRATION_CSV_COLUMNS)
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('registrations.title')}</h1>
          <p className="muted">
            {resp ? `${resp.total_items} ${t('common.total')}` : t('common.loading')}
          </p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => {
              setQ(e.target.value)
              setPage(1)
            }}
            placeholder={t('registrations.search_placeholder')}
            style={{ width: '200px' }}
          />
          <select
            value={status}
            onChange={(e) => {
              setStatus(e.target.value as StatusFilter)
              setPage(1)
            }}
            style={{ width: 'auto' }}
          >
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {t(`registrations.filter_${s}`)}
              </option>
            ))}
          </select>
          <ExportCsvButton onExport={exportCsv} />
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}

      <Table<AdminRegistration>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(r) => r.user_id}
        loading={loading}
        empty={t('registrations.empty')}
      />
      <Pagination
        page={page}
        totalPages={resp?.total_pages ?? 1}
        onPageChange={setPage}
        disabled={loading}
      />

      {rejecting && (
        <div
          role="dialog"
          aria-modal="true"
          onClick={() => {
            if (busyId === null) setRejecting(null)
          }}
          style={{
            position: 'fixed',
            inset: 0,
            background: 'rgba(15,23,42,0.45)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 1000,
            padding: 16,
          }}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            style={{
              background: 'var(--surface, #fff)',
              color: 'inherit',
              borderRadius: 16,
              padding: 22,
              width: 'min(460px, 100%)',
              boxShadow: '0 24px 60px -20px rgba(0,0,0,0.5)',
            }}
          >
            <h3 style={{ margin: '0 0 6px' }}>{t('registrations.reject_title')}</h3>
            <p className="muted" style={{ margin: '0 0 14px', fontSize: 13 }}>
              {t('registrations.reject_hint')}
            </p>
            <textarea
              autoFocus
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder={t('registrations.reason_placeholder')}
              rows={3}
              style={{ width: '100%', resize: 'vertical' }}
            />
            <div
              className="row"
              style={{ justifyContent: 'flex-end', gap: 8, marginTop: 16 }}
            >
              <button
                className="secondary"
                disabled={busyId !== null}
                onClick={() => {
                  setRejecting(null)
                  setReason('')
                }}
              >
                {t('common.cancel')}
              </button>
              <button
                className="danger"
                disabled={busyId !== null}
                onClick={doReject}
              >
                {t('registrations.reject')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
