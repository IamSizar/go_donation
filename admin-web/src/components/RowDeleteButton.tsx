import { isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'

// Role-aware row delete control (global notice #5). The Super-Admin sees
// "Delete"; every other staff member sees "Archive". Both trigger the SAME
// action — records move to the Trash either way — but only the Super-Admin can
// later permanently purge them (with a PIN) from the Trash page.
export default function RowDeleteButton({
  onClick,
  className,
}: {
  onClick: () => void
  className?: string
}) {
  const { user } = useAuth()
  const { t } = useI18n()
  const canDelete = isSuperAdmin(user)
  return (
    <button className={className ?? 'row-delete-btn'} onClick={onClick}>
      {canDelete ? t('common.delete') : t('action.archive')}
    </button>
  )
}
