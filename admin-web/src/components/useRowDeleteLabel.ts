// useRowDeleteLabel.ts — the label RowDeleteButton would render.
//
// Split out of RowDeleteButton.tsx because a file that exports a component may
// not also export a hook: Vite's fast refresh can only swap a module whose
// exports are all components (react-refresh/only-export-components).

import { isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'

/** The label RowDeleteButton would render, for use inside a menu item where
 *  the button itself isn't rendered. Same role rule: Super-Admin deletes,
 *  everyone else archives — both routes the record to Trash. */
export function useRowDeleteLabel(): string {
  const { user } = useAuth()
  const { t } = useI18n()
  return isSuperAdmin(user) ? t('common.delete') : t('action.archive')
}
