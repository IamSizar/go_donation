// DashboardPage — refreshed with framer-motion staggered entrance and a
// hero "welcome back" greeting that pulls the signed-in admin's name.
//
// Animation orchestration:
//   • Page-level container variant defines staggerChildren so sections
//     fade in one-by-one rather than all-at-once.
//   • Each section is a motion.section with its own variants — they
//     inherit the parent stagger automatically.
//   • TrendCards each animate themselves on mount (initial → animate),
//     so the stat grid feels alive even without per-card stagger here.

import { useCallback, useEffect, useMemo, useState } from 'react'
import { motion, type Variants } from 'framer-motion'
import { api, describeError } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'
import { useLivePoll } from '../lib/useLivePoll'
import type { DashboardKPIs, DashboardKPIsResp } from '../lib/api-types'
import TrendCard from '../components/TrendCard'
import DonationsChart from '../components/DonationsChart'
import EventsFeed from '../components/EventsFeed'

function formatMoney(s: string | number): string {
  const n = typeof s === 'number' ? s : parseFloat(s)
  if (!isFinite(n)) return String(s)
  return n.toLocaleString()
}

// Cascading entrance: parent runs staggerChildren so each section pops in
// 80ms after the previous one. Children inherit `show` automatically.
const containerVariants: Variants = {
  hidden: { opacity: 0 },
  show: {
    opacity: 1,
    transition: { staggerChildren: 0.08, delayChildren: 0.05 },
  },
}

const sectionVariants: Variants = {
  hidden: { opacity: 0, y: 16 },
  show: { opacity: 1, y: 0, transition: { type: 'spring', stiffness: 110, damping: 18 } },
}

export default function DashboardPage() {
  const [kpis, setKpis] = useState<DashboardKPIs | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const { user } = useAuth()
  const { t } = useI18n()

  // Initial load — flips the loading flag so the first render shows
  // skeletons in the trend cards. Subsequent live-polls don't toggle
  // loading so the numbers update smoothly in place.
  useEffect(() => {
    let cancelled = false
    api
      .get<DashboardKPIsResp>('/api/admin/dashboard_kpis')
      .then((r) => { if (!cancelled) setKpis(r.data.kpis) })
      .catch((e) => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [])

  // Phase 27 — live refresh every 10s while the tab is visible.
  // Aggregated KPIs don't move minute-to-minute, so 10s is plenty.
  // Errors during a silent poll just keep the previous numbers on
  // screen — no need to clear the dashboard mid-session.
  const livePoll = useCallback(async () => {
    try {
      const r = await api.get<DashboardKPIsResp>('/api/admin/dashboard_kpis')
      setKpis(r.data.kpis)
      setErr(null)
    } catch {
      // swallow — keep the last good snapshot visible
    }
  }, [])
  useLivePoll(livePoll, 10_000)

  const greeting = useMemo(() => {
    const h = new Date().getHours()
    if (h < 12) return t('page.dashboard.good_morning')
    if (h < 18) return t('page.dashboard.good_afternoon')
    return t('page.dashboard.good_evening')
  }, [t])
  const firstName = user?.phone ? `#${user.user_id}` : 'admin'

  return (
    <motion.div
      className="stack"
      variants={containerVariants}
      initial="hidden"
      animate="show"
    >
      {/* Hero: greeting + subtle metric callout */}
      <motion.div variants={sectionVariants} className="dashboard-hero">
        <div>
          <p className="muted" style={{ margin: 0, letterSpacing: '0.04em' }}>
            {greeting}, {firstName}.
          </p>
          <h1 style={{ margin: '4px 0 0 0' }}>{t('page.dashboard.title')}</h1>
        </div>
        {kpis && (
          <motion.div
            className="dashboard-hero-stat"
            initial={{ opacity: 0, x: 12 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.25, type: 'spring', stiffness: 120, damping: 20 }}
          >
            <span className="muted">{t('page.dashboard.snapshot')}</span>
            <strong>{t('page.dashboard.snapshot_line', { count: kpis.donations_count.this_month, amount: formatMoney(kpis.donations_amount.this_month) })}</strong>
          </motion.div>
        )}
      </motion.div>

      {err && <div className="error-box">{err}</div>}

      <motion.section variants={sectionVariants} className="stat-grid">
        <TrendCard
          label={t('page.dashboard.signups_month')}
          value={loading ? '…' : kpis?.signups.this_month ?? 0}
          pctChange={kpis?.signups.pct_change}
          sublabel={kpis ? t('page.dashboard.vs_last_month', { n: kpis.signups.last_month }) : undefined}
          loading={loading}
        />
        <TrendCard
          label={t('page.dashboard.donations_month')}
          value={loading ? '…' : kpis?.donations_count.this_month ?? 0}
          pctChange={kpis?.donations_count.pct_change}
          sublabel={kpis ? t('page.dashboard.vs_last_month', { n: kpis.donations_count.last_month }) : undefined}
          loading={loading}
        />
        <TrendCard
          label={t('page.dashboard.completed_month')}
          value={loading ? '…' : kpis ? `${formatMoney(kpis.donations_amount.this_month)} IQD` : '—'}
          pctChange={kpis?.donations_amount.pct_change}
          sublabel={
            kpis
              ? t('page.dashboard.vs_last_month', { n: formatMoney(kpis.donations_amount.last_month) })
              : undefined
          }
          loading={loading}
        />
        <TrendCard
          label={t('page.dashboard.active_campaigns')}
          value={loading ? '…' : kpis?.active_campaigns ?? 0}
          loading={loading}
        />
        <TrendCard
          label={t('page.dashboard.open_missions')}
          value={loading ? '…' : kpis?.open_missions ?? 0}
          loading={loading}
        />
        <TrendCard
          label={t('page.dashboard.open_tickets')}
          value={loading ? '…' : kpis?.open_tickets ?? 0}
          loading={loading}
        />
      </motion.section>

      <motion.section variants={sectionVariants} className="card">
        <h2 style={{ margin: '0 0 12px 0' }}>{t('page.dashboard.donations_30d')}</h2>
        <DonationsChart data={kpis?.donations_30d ?? []} loading={loading} />
      </motion.section>

      <motion.section variants={sectionVariants}>
        <EventsFeed />
      </motion.section>
    </motion.div>
  )
}
