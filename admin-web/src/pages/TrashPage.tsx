// TrashPage — Phase 7 (G-06 / A-16). The recovery bin for every admin delete.
//
// Deletes across the dashboard no longer destroy rows; the backend snapshots
// each one into trash_items as a JSON document. Here an admin can Restore a
// record (re-inserted from that snapshot) or permanently Purge it — purge is
// PIN-gated (re-enter your password) and only offered to the Super-Admin.
import { useCallback, useEffect, useState } from 'react'
import { api, describeError, canExportData, isSuperAdmin } from '../lib/api'
import { askForText } from '../lib/dialogs'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import Table, { type Column } from '../components/Table'
import PageHead from '../components/PageHead'
import { fmtId } from '../lib/formatId'

type TrashItem = {
  id: number
  source_table: string
  row_id: number
  deleted_by: number | null
  deleted_by_name: string | null
  deleted_at: string
  payload: Record<string, unknown>
}

// Friendly module label per source table, resolved via existing nav keys so it
// localizes; falls back to the raw table name (a technical DB value).
const MODULE_TKEY: Record<string, string> = {
  partners: 'nav.partners',
  media_posts: 'nav.media',
  city_directory_entries: 'nav.city_guide',
  marriage_profiles: 'nav.marriage',
  marketplace_products: 'nav.marketplace',
  marketplace_orders: 'nav.marketplace',
  beneficiary_cases: 'nav.beneficiary',
  beneficiary_project_requests: 'nav.beneficiary',
  sponsorships: 'nav.sponsorships',
  in_kind_donations: 'nav.in_kind',
  support_tickets: 'nav.support',
  donations: 'nav.donations',
  volunteer_applications: 'nav.volunteers',
  campaigns: 'nav.campaigns',
  users: 'nav.users',
  volunteer_missions: 'nav.missions',

  // H15 — the thirteen routes that used to delete permanently. Each maps to
  // the section it is managed in, because this column is the MODULE, not the
  // record type. Without an entry here the table would print the raw source
  // table name — an English database token in an Arabic dashboard.
  custom_professions: 'nav.volunteers',
  project_categories: 'nav.project_categories',
  sponsorship_types: 'nav.sponsorship_types',
  inkind_categories: 'nav.in_kind',
  city_sectors: 'nav.city_sectors',
  city_categories: 'nav.city_categories',
  media_categories: 'nav.media_categories',
  case_categories: 'nav.beneficiary',
  marketplace_categories: 'nav.marketplace_categories',
  payment_methods: 'nav.payment_methods',
  // M7 — donation types are deleted through trashRow like every sibling list,
  // so without this entry the Trash would print the raw table name.
  donation_types: 'nav.donation_types',
  marriage_subscription_packages: 'nav.marriage_subscriptions',
  tasks: 'nav.tasks',
  post_comments: 'nav.comments',

  // E15 — the new recoverable delete on تسجيلات المهام. Without this entry the
  // Trash would print the raw `volunteer_mission_signups` — an English database
  // token on an Arabic screen — which is the exact defect the block above
  // exists to prevent.
  volunteer_mission_signups: 'nav.volunteers',
}

// Pull a human-readable label out of the snapshot to help identify the record.
//
// H15 — the catalogue rows that now reach the Trash store their display text in
// per-language columns (`name_ar`, `label_en`, …), not a bare `name`, and a
// comment's text lives in `body`. Without those the Trash showed a bare id and
// an admin had to guess what they were about to restore. Reading order: the
// admin's own language first, then Arabic, then English.
function previewOf(payload: Record<string, unknown>, locale: string): string {
  const localized = ['name', 'label', 'title'].flatMap((base) => [
    `${base}_${locale}`, `${base}_ar`, `${base}_en`,
  ])
  const cand = [
    'full_name', ...localized, 'title', 'name', 'product_name',
    'reference', 'ref', 'username', 'phone', 'email',
    'body', 'word', // a moderated comment; a blocked word
    // E15 — a mission signup carries no name/title of its own; `notes` is the
    // only free text on the row. Last in the list on purpose: it exists on
    // several other tables too, and must never win over a real name there.
    'notes',
  ]
  for (const k of cand) {
    const v = payload?.[k]
    if (typeof v === 'string' && v.trim()) {
      const s = v.trim()
      // A comment body can be a paragraph; the Trash needs a handle, not the text.
      return s.length > 60 ? `${s.slice(0, 60)}…` : s
    }
  }
  return ''
}

export default function TrashPage() {
  const { user } = useAuth()
  const { t, locale } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<TrashItem[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<number | null>(null)
  const [selected, setSelected] = useState<Set<number>>(new Set())

  const allowed = canExportData(user)
  // Permanent deletion is restricted to the Primary Administrator only
  // (Section 25) — the backend also enforces RequireSuperAdmin on purge.
  const canPurge = isSuperAdmin(user)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const { data } = await api.get<{ items: TrashItem[] }>('/api/admin/trash')
      setItems(data.items ?? [])
      setErr(null)
    } catch (e) {
      setErr(describeError(e))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { if (allowed) void load() }, [allowed, load])

  // Note #26 — used to restore with a single click and no confirmation, so
  // any admin tier could accidentally (or casually) bring back a deleted
  // record. PIN-gated the same way Purge already is: prompt for the acting
  // admin's own password and let the backend verify it (A-16 pattern).
  const restore = async (it: TrashItem) => {
    if (busyId) return
    const pin = await askForText({
      title: t('auth.password'),
      message: t('page.trash.restore_prompt'),
      secret: true,
    })
    if (pin == null) return
    if (!pin.trim()) { toast.error(t('export.pin_required')); return }
    setBusyId(it.id)
    try {
      await api.post(`/api/admin/trash/${it.id}/restore`, { password: pin })
      toast.success(t('page.trash.restored'))
      await load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyId(null)
    }
  }

  const purge = async (it: TrashItem) => {
    if (busyId) return
    // Destructive: the record does not come back from this one, and the
    // message says so. Red primary button rather than the neutral one the
    // reversible Restore above gets.
    const pin = await askForText({
      title: t('auth.password'),
      message: t('page.trash.purge_prompt'),
      secret: true,
      destructive: true,
    })
    if (pin == null) return
    if (!pin.trim()) { toast.error(t('export.pin_required')); return }
    setBusyId(it.id)
    try {
      await api.post(`/api/admin/trash/${it.id}/purge`, { password: pin })
      toast.success(t('page.trash.purged'))
      await load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyId(null)
    }
  }

  const toggle = (id: number) =>
    setSelected((s) => {
      const n = new Set(s)
      if (n.has(id)) n.delete(id)
      else n.add(id)
      return n
    })
  const toggleAll = () =>
    setSelected((s) => (s.size === items.length ? new Set() : new Set(items.map((it) => it.id))))

  // Bulk permanent purge (super-admin) — one PIN prompt, then purge each selected.
  const purgeSelected = async () => {
    if (selected.size === 0 || busyId) return
    const pin = await askForText({
      title: t('auth.password'),
      message: t('page.trash.purge_prompt'),
      secret: true,
      destructive: true,
    })
    if (pin == null) return
    if (!pin.trim()) { toast.error(t('export.pin_required')); return }
    const ids = [...selected]
    let ok = 0
    for (const id of ids) {
      try {
        await api.post(`/api/admin/trash/${id}/purge`, { password: pin })
        ok++
      } catch {
        /* keep going; report the successful count */
      }
    }
    toast.success(t('page.trash.purged_n', { n: ok }))
    setSelected(new Set())
    await load()
  }

  if (!allowed) {
    return (
      <div className="stack">
        <div className="error-box">{t('page.trash.no_access')}</div>
      </div>
    )
  }

  const selectCol: Column<TrashItem> = {
    key: 'sel', header: '', width: '38px',
    cell: (it) => (
      <input
        type="checkbox"
        checked={selected.has(it.id)}
        onChange={() => toggle(it.id)}
        aria-label={t('common.select_row')}
      />
    ),
  }

  const columns: Column<TrashItem>[] = [
    ...(canPurge ? [selectCol] : []),
    { key: 'module', header: t('page.trash.col_module'), cell: (it) => (
      MODULE_TKEY[it.source_table]
        ? <strong>{t(MODULE_TKEY[it.source_table])}</strong>
        : <code style={{ background: 'transparent', padding: 0 }}>{it.source_table}</code>
    ) },
    { key: 'record', header: t('page.trash.col_record'), cell: (it) => (
      <div className="cell-stack">
        <strong>{fmtId(it.row_id)}</strong>
        {previewOf(it.payload, locale) && <span className="muted">{previewOf(it.payload, locale)}</span>}
      </div>
    ) },
    { key: 'by', header: t('page.trash.col_deleted_by'), cell: (it) => it.deleted_by_name || <span className="muted">—</span> },
    { key: 'at', header: t('page.trash.col_deleted_at'), cell: (it) => <span className="muted">{it.deleted_at?.slice(0, 16).replace('T', ' ')}</span> },
    {
      // Note #26 — the header text was left-aligned by default while the
      // button group inside the cell was pushed to the right via flexbox
      // (justifyContent: 'flex-end'), so "Actions" visibly sat over empty
      // space instead of over the buttons it labels. Align the header to
      // match where the data actually renders.
      key: 'actions', header: t('common.actions'), align: 'right', cell: (it) => (
      <div className="row" style={{ gap: 6, justifyContent: 'flex-end' }}>
        <button className="secondary" disabled={busyId === it.id} onClick={() => restore(it)}>
          {t('action.restore')}
        </button>
        {canPurge && (
          <button className="danger" disabled={busyId === it.id} onClick={() => purge(it)}>
            {t('action.purge')}
          </button>
        )}
      </div>
    ) },
  ]

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('page.trash.title')}</h1>
          <p className="muted">
            {loading ? t('common.loading') : t('page.trash.subtitle', { n: items.length })}
          </p>
        </div>
        {canPurge && items.length > 0 && (
          <div className="row" style={{ gap: 12, alignItems: 'center' }}>
            <label className="row" style={{ gap: 6, alignItems: 'center', cursor: 'pointer' }}>
              <input
                type="checkbox"
                checked={selected.size === items.length}
                onChange={toggleAll}
              />
              <span className="muted">{t('page.trash.select_all')}</span>
            </label>
            <button className="danger" disabled={selected.size === 0} onClick={purgeSelected}>
              {t('page.trash.purge_selected', { n: selected.size })}
            </button>
          </div>
        )}
      </PageHead>
      {err && <div className="error-box">{err}</div>}
      <Table<TrashItem>
        rows={items}
        columns={columns}
        rowKey={(it) => it.id}
        loading={loading}
        empty={t('page.trash.empty')}
      />
    </div>
  )
}
