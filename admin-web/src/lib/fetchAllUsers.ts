// fetchAllUsers — every account matching `params`, page by page.
//
// WHY THIS EXISTS. /api/admin/users serves at most 100 rows a page, and a
// larger per_page is not clamped to 100 — it falls back to the default of 20
// (users.PaginatedList). Four screens asked for 200 or 1000 "to get everyone"
// and silently got the newest 20 accounts: the Staff page showed no staff at
// all once 20 app users had registered after the last staff account, and the
// Permissions picker, the Receipts recipient picker and the detail pages'
// user-name lookup were all limited to those same 20.
import { api } from './api'
import type { UserAccount, UsersListResp } from './api-types'

/** The server's real page ceiling. */
const PAGE_SIZE = 100
/** A backstop against a server that never reports the last page. */
const MAX_PAGES = 200

export async function fetchAllUsers(params: Record<string, string | number | undefined> = {}): Promise<UserAccount[]> {
  const out: UserAccount[] = []
  for (let page = 1; page <= MAX_PAGES; page++) {
    const { data } = await api.get<UsersListResp>('/api/admin/users', {
      params: { ...params, page, per_page: PAGE_SIZE },
    })
    const rows = data.data ?? []
    out.push(...rows)
    if (!data.pagination?.has_more || rows.length === 0) break
  }
  return out
}
