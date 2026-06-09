import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import type { ReportsResp } from '../lib/api-types'
import StatCard from '../components/StatCard'
import { useI18n } from '../lib/i18n'

function fmt(s: string | number): string {
  const n = typeof s === 'number' ? s : parseFloat(s)
  if (!isFinite(n)) return String(s)
  return n.toLocaleString()
}

export default function ReportsPage() {
  const [resp, setResp] = useState<ReportsResp | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const { t } = useI18n()

  useEffect(() => {
    let cancelled = false
    api.get<ReportsResp>('/api/reports')
      .then(r => { if (!cancelled) setResp(r.data) })
      .catch(e => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [])

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.reports.title')}</h1>
          <p className="muted">{t('page.reports.subtitle')}</p>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}

      <section>
        <h2>{t('page.donations.title')}</h2>
        <div className="stat-grid">
          <StatCard label={t('col.total')} value={loading ? '…' : resp?.donations.total_count ?? '—'} />
          <StatCard label={t('page.reports.completed_iqd')} value={loading ? '…' : resp ? fmt(resp.donations.completed_amount) : '—'} />
          <StatCard label={t('page.reports.pending_iqd')} value={loading ? '…' : resp ? fmt(resp.donations.pending_amount) : '—'} />
          <StatCard label={t('page.reports.failed_iqd')} value={loading ? '…' : resp ? fmt(resp.donations.failed_amount) : '—'} />
        </div>
      </section>

      <section>
        <h2>{t('nav.volunteers')}</h2>
        <div className="stat-grid">
          <StatCard label={t('page.reports.applications')} value={loading ? '…' : resp?.volunteers.applications_total ?? '—'}
            hint={resp ? t('page.reports.approved_hint', { n: resp.volunteers.applications_approved }) : undefined} />
          <StatCard label={t('page.reports.missions_open')} value={loading ? '…' : resp?.volunteers.missions_open ?? '—'} />
          <StatCard label={t('page.reports.missions_completed')} value={loading ? '…' : resp?.volunteers.missions_completed ?? '—'} />
          <StatCard label={t('page.reports.signups_pending')} value={loading ? '…' : resp?.volunteers.signups_pending ?? '—'} />
          <StatCard label={t('page.reports.signups_active')} value={loading ? '…' : resp?.volunteers.signups_active ?? '—'} />
          <StatCard label={t('page.reports.hours_served')} value={loading ? '…' : resp ? fmt(resp.volunteers.hours_served) : '—'} />
        </div>
      </section>

      <section className="two-col">
        <div className="card">
          <h2>{t('page.reports.beneficiary_cases')}</h2>
          <BucketList items={resp?.beneficiary_cases ?? []} loading={loading} />
        </div>
        <div className="card">
          <h2>{t('page.beneficiary.tab_requests')}</h2>
          <BucketList items={resp?.project_requests ?? []} loading={loading} />
        </div>
      </section>

      <section className="two-col">
        <div className="card">
          <h2>{t('page.reports.signup_statuses')}</h2>
          <BucketList items={resp?.volunteer_signup_statuses ?? []} loading={loading} />
        </div>
        <div className="card">
          <h2>{t('page.reports.expenses_by_type')}</h2>
          {loading ? <div className="muted">{t('common.loading')}</div> :
            (resp?.expenses ?? []).length === 0 ? <div className="muted">{t('page.reports.no_expenses')}</div> :
              <ul className="key-value">
                {resp!.expenses.map(e => (
                  <li key={e.expense_type}>
                    <span>{e.expense_type}</span>
                    <strong>{fmt(e.amount)} IQD</strong>
                  </li>
                ))}
              </ul>
          }
        </div>
      </section>
    </div>
  )
}

function BucketList({ items, loading }: { items: Array<{ label: string; total: number }>, loading: boolean }) {
  const { t } = useI18n()
  if (loading) return <div className="muted">{t('common.loading')}</div>
  if (items.length === 0) return <div className="muted">{t('page.reports.no_data')}</div>
  return (
    <ul className="key-value">
      {items.map(b => <li key={b.label}><span>{b.label}</span><strong>{b.total}</strong></li>)}
    </ul>
  )
}
