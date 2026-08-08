import ActionsMenu, { type ActionItem } from './ActionsMenu'
import { useRowDeleteLabel } from './RowDeleteButton'
import { useI18n } from '../lib/i18n'

// The View / Edit / Delete trio that nearly every table row carries, as one
// dropdown instead of three loose buttons that wrap and crowd the column.
//
// Owns the role-aware delete label itself (Super-Admin sees "Delete",
// everyone else "Archive" — exactly what RowDeleteButton rendered), so a page
// doesn't have to pull that hook in just to build the menu.
//
// `extra` slots page-specific entries in above Edit — e.g. City Guide's
// Approve / Reject on a pending entry.
export default function RowActionsMenu({
  viewHref,
  onEdit,
  onDelete,
  extra,
}: {
  viewHref: string
  onEdit: () => void
  onDelete?: () => void
  extra?: ActionItem[]
}) {
  const { t } = useI18n()
  const deleteLabel = useRowDeleteLabel()
  const items: ActionItem[] = [
    { key: 'view', label: t('common.view'), href: viewHref, onClick: () => {} },
    ...(extra ?? []),
    { key: 'edit', label: t('common.edit'), onClick: onEdit },
  ]
  if (onDelete) {
    items.push({ key: 'delete', label: deleteLabel, onClick: onDelete, danger: true })
  }
  return <ActionsMenu items={items} />
}
