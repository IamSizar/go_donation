/**
 * "New conversation" picker for Staff Chat.
 *
 * Replaces an inline list of default <button>s: on this theme every button is
 * a solid green pill, so thirteen of them stacked above the chat read as a wall
 * of green, and the grey tier/phone text on green was unreadable. This is a
 * normal dialog instead — a search box first (the operator usually knows who
 * they want), then quiet rows that only highlight on hover.
 *
 * Search matches the name, the phone digits and the translated tier, so
 * "مشرف", "0750" or "ahmed" all narrow the list. Enter opens the first match;
 * Escape or a click on the backdrop closes.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { api, describeError } from '../lib/api'
import { useI18n, useStatusLabel } from '../lib/i18n'

export type DirectoryEntry = {
  user_id: number
  full_name: string | null
  phone: string
  staff_tier: string
}

type Props = {
  open: boolean
  onClose: () => void
  /** Opens (or creates) the conversation. The dialog stays up, disabled,
   *  until this settles, so a slow start can't be clicked twice. */
  onPick: (userId: number) => Promise<void>
  /** People the operator already has a conversation with — marked, since
   *  picking them re-opens that chat rather than starting a second one. */
  existingUserIds?: ReadonlySet<number>
}

const TIER_TONE: Record<string, string> = {
  super_admin: 'tone-primary',
  admin: 'tone-info',
  supervisor: 'tone-warning',
  employee: '',
}

function displayName(d: DirectoryEntry): string {
  return d.full_name && d.full_name.trim() ? d.full_name.trim() : `#${d.user_id}`
}

const hasName = (d: DirectoryEntry) => !!d.full_name?.trim()

/** One or two letters for the avatar; works for Arabic and Latin names.
 *  Only called for named accounts — unnamed ones get a person icon. */
function initials(d: DirectoryEntry): string {
  const n = d.full_name!.trim()
  const parts = n.split(/\s+/).filter(Boolean)
  const first = [...parts[0]][0] ?? ''
  const second = parts.length > 1 ? [...parts[parts.length - 1]][0] ?? '' : ''
  return (first + second).toUpperCase()
}

export default function StaffPickerModal({ open, ...rest }: Props) {
  // The card is mounted only while open, so every opening starts with a fresh
  // list, an empty search and no leftover error — no reset logic needed.
  return <AnimatePresence>{open && <PickerCard {...rest} />}</AnimatePresence>
}

function PickerCard({ onClose, onPick, existingUserIds }: Omit<Props, 'open'>) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const [entries, setEntries] = useState<DirectoryEntry[] | null>(null)
  const [loadErr, setLoadErr] = useState<string | null>(null)
  const [q, setQ] = useState('')
  const [busyId, setBusyId] = useState<number | null>(null)
  const [pickErr, setPickErr] = useState<string | null>(null)
  const searchRef = useRef<HTMLInputElement | null>(null)

  const fetchDirectory = useCallback(async () => {
    try {
      const res = await api.get<{ items: DirectoryEntry[] }>('/api/admin/staff-directory')
      setEntries(res.data.items ?? [])
    } catch (e) {
      setLoadErr(describeError(e))
    }
  }, [])

  const retry = () => {
    setLoadErr(null)
    setEntries(null)
    fetchDirectory()
  }

  useEffect(() => {
    // `fetchDirectory` only calls setState after awaiting the request, so
    // nothing here is synchronous and no cascading render happens. The rule
    // reports it anyway because it steps into a useCallback without modelling
    // the await (same as loadThreads on the chat pages).
    // eslint-disable-next-line react-hooks/set-state-in-effect
    fetchDirectory()
    const id = window.setTimeout(() => searchRef.current?.focus(), 60)
    return () => window.clearTimeout(id)
  }, [fetchDirectory])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape' && busyId === null) onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [busyId, onClose])

  const filtered = useMemo(() => {
    // Alphabetical, with accounts that have no profile name ("#61") last.
    const list = [...(entries ?? [])].sort((a, b) =>
      Number(hasName(b)) - Number(hasName(a)) ||
      displayName(a).localeCompare(displayName(b), undefined, { sensitivity: 'base' }))
    const needle = q.trim().toLowerCase()
    if (!needle) return list
    const digits = needle.replace(/\D/g, '')
    return list.filter((d) =>
      displayName(d).toLowerCase().includes(needle) ||
      statusLabel(d.staff_tier).toLowerCase().includes(needle) ||
      (digits.length > 0 && d.phone.replace(/\D/g, '').includes(digits)))
  }, [entries, q, statusLabel])

  async function pick(userId: number) {
    if (busyId !== null) return
    setBusyId(userId)
    setPickErr(null)
    try {
      await onPick(userId)
    } catch (e) {
      setPickErr(describeError(e))
    } finally {
      setBusyId(null)
    }
  }

  return (
    <motion.div
      className="modal-overlay"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.18 }}
      onMouseDown={(e) => { if (e.target === e.currentTarget && busyId === null) onClose() }}
    >
      <motion.div
        className="modal-card staff-picker"
        role="dialog"
        aria-modal="true"
        aria-labelledby="staff-picker-title"
        initial={{ opacity: 0, scale: 0.96, y: 10 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.97, y: 6 }}
        transition={{ type: 'spring', stiffness: 320, damping: 28 }}
      >
        <div className="modal-head">
          <h2 id="staff-picker-title">{t('page.staff_chat.new_title')}</h2>
          <button type="button" className="icon" aria-label={t('common.close')} onClick={onClose} disabled={busyId !== null}>×</button>
        </div>

        <div className="staff-picker-search">
          <input
            ref={searchRef}
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && filtered.length > 0) { e.preventDefault(); pick(filtered[0].user_id) }
            }}
            placeholder={t('page.staff_chat.search_placeholder')}
            aria-label={t('page.staff_chat.search_placeholder')}
          />
        </div>

        <div className="modal-body staff-picker-body">
          {pickErr && <div className="error-box" style={{ marginBottom: 10 }}>{pickErr}</div>}
          {loadErr ? (
            <div className="staff-picker-state">
              <span>{loadErr}</span>
              <button type="button" className="secondary" onClick={retry}>{t('error.retry')}</button>
            </div>
          ) : entries === null ? (
            <div className="staff-picker-state muted">{t('common.loading')}</div>
          ) : filtered.length === 0 ? (
            <div className="staff-picker-state muted">
              {entries.length === 0 ? t('page.staff_chat.no_staff') : t('page.staff_chat.no_matches')}
            </div>
          ) : (
            <ul className="staff-picker-list">
              {filtered.map((d) => {
                const busy = busyId === d.user_id
                return (
                  <li key={d.user_id}>
                    <button
                      type="button"
                      className="staff-picker-row"
                      onClick={() => pick(d.user_id)}
                      disabled={busyId !== null}
                      aria-busy={busy}
                    >
                      <span className="staff-picker-avatar" aria-hidden="true">
                          {hasName(d) ? initials(d) : (
                            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                              <circle cx="12" cy="8" r="4" />
                              <path d="M4 21c0-4 3.6-7 8-7s8 3 8 7" />
                            </svg>
                          )}
                        </span>
                      <span className="staff-picker-text">
                        <span className="staff-picker-name">{displayName(d)}</span>
                        <span className="staff-picker-meta">
                          <span className={`badge ${TIER_TONE[d.staff_tier] ?? ''}`.trim()}>{statusLabel(d.staff_tier)}</span>
                          {d.phone && <span className="staff-picker-phone" dir="ltr">{d.phone}</span>}
                        </span>
                      </span>
                      <span className="staff-picker-end muted">
                        {busy
                          ? t('common.loading')
                          : existingUserIds?.has(d.user_id)
                            ? t('page.staff_chat.existing')
                            : null}
                      </span>
                    </button>
                  </li>
                )
              })}
            </ul>
          )}
        </div>
      </motion.div>
    </motion.div>
  )
}
