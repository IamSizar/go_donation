import { useI18n } from '../lib/i18n'

type Props = {
  page: number
  totalPages: number
  onPageChange: (page: number) => void
  disabled?: boolean
}

export default function Pagination({ page, totalPages, onPageChange, disabled }: Props) {
  const { t } = useI18n()
  if (totalPages <= 1) return null
  return (
    <div className="pagination">
      <button
        className="secondary"
        disabled={disabled || page <= 1}
        onClick={() => onPageChange(page - 1)}
      >
        ← {t('common.previous')}
      </button>
      <span className="muted">
        {t('common.page')} <strong>{page}</strong> {t('common.of')} <strong>{totalPages}</strong>
      </span>
      <button
        className="secondary"
        disabled={disabled || page >= totalPages}
        onClick={() => onPageChange(page + 1)}
      >
        {t('common.next')} →
      </button>
    </div>
  )
}
