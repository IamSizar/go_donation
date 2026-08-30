import { ChevronLeft, ChevronRight } from 'lucide-react'
import { useI18n } from '../lib/i18n'

type Props = {
  page: number
  totalPages: number
  onPageChange: (page: number) => void
  disabled?: boolean
}

// Pagination controls. The arrows are direction-aware rather than hardcoded
// LTR glyphs: "next" always points toward the END of the reading direction
// and "previous" toward the START. In English that's next→right,
// previous→left; in Arabic (RTL) it flips — next points LEFT, previous
// points RIGHT. A fixed "←"/"→" pair used to stay pointing the English way
// under Arabic, which silently told an Arabic user "next" meant "back".
export default function Pagination({ page, totalPages, onPageChange, disabled }: Props) {
  const { t, dir } = useI18n()
  if (totalPages <= 1) return null
  const isRtl = dir === 'rtl'
  // In RTL, "previous" (toward the start) visually points right; "next"
  // (toward the end) visually points left. Swap the icons accordingly.
  const PreviousIcon = isRtl ? ChevronRight : ChevronLeft
  const NextIcon = isRtl ? ChevronLeft : ChevronRight
  return (
    <div className="pagination">
      <button
        className="secondary"
        disabled={disabled || page <= 1}
        onClick={() => onPageChange(page - 1)}
      >
        <PreviousIcon size={16} aria-hidden="true" />
        {t('common.previous')}
      </button>
      <span className="muted">
        {t('common.page')} <strong>{page}</strong> {t('common.of')} <strong>{totalPages}</strong>
      </span>
      <button
        className="secondary"
        disabled={disabled || page >= totalPages}
        onClick={() => onPageChange(page + 1)}
      >
        {t('common.next')}
        <NextIcon size={16} aria-hidden="true" />
      </button>
    </div>
  )
}
