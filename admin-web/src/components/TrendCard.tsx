// TrendCard — Phase "polish": animated KPI tile.
//
// Visual changes:
//   • Gradient accent stripe down the left edge, colored by trend
//     (green up, red down, neutral grey).
//   • Spring-loaded hover lift (translate + box-shadow).
//   • The numeric value animates from 0 to its target on mount /
//     whenever the value changes (counter rolls up).
//
// Animation principles followed:
//   • Animate transform + opacity only (compositor-friendly).
//   • Spring transitions for hover (feels physical, not mechanical).
//   • Counter uses motion values so it bypasses React re-renders.

import { useEffect } from 'react'
import type { ReactNode } from 'react'
import { motion, useMotionValue, useSpring, useTransform } from 'framer-motion'

type Props = {
  label: string
  value: ReactNode
  pctChange?: number
  sublabel?: string
  loading?: boolean
}

function trendClass(pct: number | undefined): string {
  if (pct === undefined) return 'neutral'
  if (pct > 0.5) return 'positive'
  if (pct < -0.5) return 'negative'
  return 'neutral'
}

function trendArrow(pct: number | undefined): string {
  if (pct === undefined) return ''
  if (pct > 0.5) return '↑'
  if (pct < -0.5) return '↓'
  return '–'
}

function trendText(pct: number | undefined): string {
  if (pct === undefined) return ''
  const sign = pct > 0 ? '+' : ''
  return `${sign}${pct.toFixed(1)}%`
}

// Pull a numeric value out of the heterogeneous `value` prop. The dashboard
// passes strings like "150,000 IQD" too — for those we strip non-digits to
// animate the leading number, then re-suffix whatever followed.
function splitValue(v: ReactNode): { num: number; suffix: string } | null {
  if (typeof v === 'number') return { num: v, suffix: '' }
  if (typeof v !== 'string') return null
  // Match leading digit-group(s) with optional commas/dots
  const m = v.match(/^([\d,.\s]+)(.*)$/)
  if (!m) return null
  const n = parseFloat(m[1].replace(/[,\s]/g, ''))
  if (!isFinite(n)) return null
  return { num: n, suffix: m[2] }
}

function AnimatedNumber({ value, suffix }: { value: number; suffix: string }) {
  // motionValue → spring → transformed text. Bypasses React state on every
  // tick, so even rapid value changes don't thrash re-renders.
  const mv = useMotionValue(0)
  const spring = useSpring(mv, { stiffness: 80, damping: 18, mass: 0.6 })
  const display = useTransform(spring, (n) => Math.round(n).toLocaleString())
  useEffect(() => { mv.set(value) }, [value, mv])
  return (
    <span>
      <motion.span>{display}</motion.span>
      {suffix}
    </span>
  )
}

export default function TrendCard({ label, value, pctChange, sublabel, loading }: Props) {
  const cls = trendClass(pctChange)
  const split = !loading ? splitValue(value) : null

  return (
    <motion.div
      className={`stat-card stat-card-${cls}`}
      // Spring-lift on hover. translateY + scale are transform-only.
      whileHover={{ y: -4, scale: 1.015 }}
      transition={{ type: 'spring', stiffness: 380, damping: 25 }}
      // Fade in on first mount (parent stagger orchestrates timing).
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
    >
      <div className="stat-stripe" aria-hidden="true" />
      <div className="stat-label">{label}</div>
      <div className="stat-value">
        {loading
          ? <span className="muted">…</span>
          : split
            ? <AnimatedNumber value={split.num} suffix={split.suffix} />
            : value}
      </div>
      <div className={`trend-pill trend-${cls}`}>
        <span>{trendArrow(pctChange)}</span>
        <span>{trendText(pctChange)}</span>
        {sublabel && <span className="muted" style={{ marginLeft: 6 }}>{sublabel}</span>}
      </div>
    </motion.div>
  )
}
