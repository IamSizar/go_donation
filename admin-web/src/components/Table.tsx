import type { ReactNode } from 'react'
import { motion } from 'framer-motion'
import { useI18n } from '../lib/i18n'

export type Column<T> = {
  key: string
  header: string
  cell: (row: T) => ReactNode
  align?: 'left' | 'right' | 'center'
  width?: string
}

// Selection support (Phase 12). When `selectable` is provided, Table renders a
// checkbox column at the far left and a "select all" checkbox in the header.
// The page owns the selection set (typically a Set<id>).
export type Selection<T> = {
  isSelected: (row: T) => boolean
  onToggle: (row: T) => void
  onToggleAll: (allCurrentRows: T[]) => void
  allSelected: boolean
}

// rowProps lets a parent attach per-row className + data-attributes for
// features like row-highlight (Phase 16). The callback runs once per row;
// returning {} (the default) keeps Table behavior identical to before.
export type RowAttrs = {
  className?: string
  // Loosely typed because callers may pass any data-* attribute (e.g.
  // data-highlight-id). React forwards these to the DOM as-is.
  [key: `data-${string}`]: string | number | undefined
}

type Props<T> = {
  rows: T[]
  columns: Column<T>[]
  rowKey: (row: T) => string | number
  empty?: ReactNode
  loading?: boolean
  selectable?: Selection<T>
  /** Optional per-row className + data-* attributes (used by the live-feed
   *  highlight feature). Merges with the built-in `row-selected` class. */
  rowProps?: (row: T) => RowAttrs | undefined
}

// Map a column's (physical) align to a LOGICAL one so headers + cells flip
// correctly under RTL (Arabic/Kurdish). 'left'→'start', 'right'→'end' — both
// track the reading direction, so a numeric column right-aligned in English
// becomes left-aligned (the row's end) in Arabic instead of staying stuck on
// the physical right. Default is 'start'. (Global notice #6.1)
function logicalAlign(a?: 'left' | 'right' | 'center'): 'start' | 'end' | 'center' {
  if (a === 'left') return 'start'
  if (a === 'right') return 'end'
  if (a === 'center') return 'center'
  return 'start'
}

export default function Table<T>({ rows, columns, rowKey, empty, loading, selectable, rowProps }: Props<T>) {
  const { t } = useI18n()
  const totalCols = columns.length + (selectable ? 1 : 0)
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead>
          <tr>
            {selectable && (
              <th style={{ width: '36px', textAlign: 'center' }}>
                <input
                  type="checkbox"
                  aria-label={t('common.select_all')}
                  checked={rows.length > 0 && selectable.allSelected}
                  onChange={() => selectable.onToggleAll(rows)}
                />
              </th>
            )}
            {columns.map((c) => (
              <th key={c.key} style={{ textAlign: logicalAlign(c.align), width: c.width }}>
                {c.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {/* Phase 27.9 — only show the placeholder row when there is NO
              data yet. During a background poll (loading=true but rows
              already present), we keep the existing rows mounted so the
              list doesn't flash/reload every few seconds. Stable row keys
              mean framer-motion won't replay the entrance animation, so
              only genuinely changed rows update in place — real-time
              without the ugly cutoff reload. */}
          {rows.length === 0 && (
            <tr>
              <td colSpan={totalCols} className="cell-muted">
                {loading ? t('common.loading') : (empty ?? t('common.no_rows'))}
              </td>
            </tr>
          )}
          {rows.length > 0 &&
            rows.map((row, idx) => {
              const selected = selectable ? selectable.isSelected(row) : false
              // Cap stagger at ~12 rows so a 50-row page doesn't take 2s to
              // animate in. Beyond that, rows just fade together.
              const staggerDelay = Math.min(idx, 12) * 0.025
              // Merge the row-selected base class with any caller-provided
              // className (e.g. "is-highlighted" from the live-feed flow).
              const extra = rowProps?.(row) ?? {}
              const className = [
                selected ? 'row-selected' : '',
                extra.className ?? '',
              ].filter(Boolean).join(' ') || undefined
              // Strip className from the spread so we don't pass it twice.
              const { className: _ignored, ...dataAttrs } = extra
              return (
                <motion.tr
                  key={rowKey(row)}
                  className={className}
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.22, delay: staggerDelay, ease: 'easeOut' }}
                  {...dataAttrs}
                >
                  {selectable && (
                    <td style={{ textAlign: 'center' }}>
                      <input
                        type="checkbox"
                        aria-label={t('common.select_row')}
                        checked={selected}
                        onChange={() => selectable.onToggle(row)}
                      />
                    </td>
                  )}
                  {columns.map((c) => (
                    <td key={c.key} style={{ textAlign: logicalAlign(c.align) }}>
                      {c.cell(row)}
                    </td>
                  ))}
                </motion.tr>
              )
            })}
        </tbody>
      </table>
    </div>
  )
}
