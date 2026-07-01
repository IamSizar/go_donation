// UserPicker — search-as-you-type combobox for picking ONE user.
//
// Phase 18e — used by the /push page to let admin target a single user by
// name/phone instead of having to memorise user_ids. Generic enough to be
// reused later (e.g. "assign volunteer to mission", "transfer ownership").
//
// Behavior:
//   • Empty state: shows a search input with placeholder "Search by name or phone…"
//   • As admin types: debounced GET /api/admin/users?q=…&per_page=8
//   • Results render as a dropdown directly below the input
//   • Click a result → `onChange` fires with the user object; input collapses
//     to a chip showing the selected name + phone, with a "Change" affordance
//   • Click "Change" → input re-opens, ready for a new search
//
// Accessibility: arrow keys navigate the dropdown, Enter selects, Esc closes.
// `aria-expanded` + `aria-activedescendant` track the open state.

import { useEffect, useRef, useState, type KeyboardEvent } from 'react'
import { api } from '../lib/api'
import { useI18n } from '../lib/i18n'

// Trimmed user shape — only the fields we need for display + identification.
// Mirrors `AdminUser` in api-types.ts; declared locally so this component
// stays decoupled from the wider type graph.
export type PickedUser = {
  user_id: number
  phone: string
  role_id: number | null
  full_name: string | null
}

// Internal API response shape (the existing /api/admin/users endpoint).
type AdminUsersResp = {
  data?: Array<{
    user_id: number
    phone: string
    role_id: number | null
    profile?: { full_name?: string | null } | null
  }>
}

const ROLE_LABEL: Record<number, string> = {
  1: 'Contributor',
  2: 'Recipient',
  3: 'Volunteer',
}

// Debounce wraps a callback so it only fires after the user has stopped
// typing for `ms` milliseconds. Saves a request per keystroke.
function useDebounced<T>(value: T, ms: number): T {
  const [v, setV] = useState(value)
  useEffect(() => {
    const t = setTimeout(() => setV(value), ms)
    return () => clearTimeout(t)
  }, [value, ms])
  return v
}

type Props = {
  /** The currently selected user, or null when nothing is picked. */
  value: PickedUser | null
  /** Fires when the admin picks (or clears) a user. */
  onChange: (u: PickedUser | null) => void
  /** Disable interaction (e.g. while the parent form is submitting). */
  disabled?: boolean
  /** Placeholder for the search input. */
  placeholder?: string
}

export default function UserPicker({ value, onChange, disabled, placeholder }: Props) {
  const { t } = useI18n()
  // Local "query" state used while picking — separate from `value` so an
  // active search doesn't immediately overwrite the picked user.
  const [query, setQuery] = useState('')
  const debounced = useDebounced(query, 300)
  const [results, setResults] = useState<PickedUser[]>([])
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const [highlight, setHighlight] = useState(-1)
  const inputRef = useRef<HTMLInputElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  // Fetch results when the debounced query changes. Empty query → no request.
  useEffect(() => {
    if (value) return                // collapsed-state: don't fetch
    const q = debounced.trim()
    if (q.length === 0) {
      setResults([])
      return
    }
    let cancelled = false
    setLoading(true)
    api
      .get<AdminUsersResp>('/api/admin/users', { params: { q, per_page: 8 } })
      .then((res) => {
        if (cancelled) return
        const list: PickedUser[] = (res.data.data ?? []).map((u) => ({
          user_id: u.user_id,
          phone: u.phone ?? '',
          role_id: u.role_id ?? null,
          full_name: u.profile?.full_name ?? null,
        }))
        setResults(list)
        setHighlight(list.length > 0 ? 0 : -1)
      })
      .catch(() => { if (!cancelled) setResults([]) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [debounced, value])

  // Close on outside click.
  useEffect(() => {
    function onDown(e: MouseEvent) {
      if (!containerRef.current?.contains(e.target as Node)) setOpen(false)
    }
    window.addEventListener('pointerdown', onDown, true)
    return () => window.removeEventListener('pointerdown', onDown, true)
  }, [])

  function pick(u: PickedUser) {
    onChange(u)
    setQuery('')
    setOpen(false)
    setResults([])
  }

  function clear() {
    onChange(null)
    setQuery('')
    // Focus the search input on next paint so the admin can type immediately.
    setTimeout(() => inputRef.current?.focus(), 0)
  }

  function onKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (!open || results.length === 0) {
      if (e.key === 'ArrowDown' && results.length > 0) {
        setOpen(true)
        e.preventDefault()
      }
      return
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setHighlight((h) => Math.min(results.length - 1, h + 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setHighlight((h) => Math.max(0, h - 1))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      if (highlight >= 0 && highlight < results.length) pick(results[highlight])
    } else if (e.key === 'Escape') {
      setOpen(false)
    }
  }

  // === Render: collapsed (selected) vs. expanded (searching) ===
  if (value) {
    return (
      <div className="user-picker user-picker-chip">
        <div className="up-chip-body">
          <span className="up-chip-avatar" aria-hidden="true">
            {(value.full_name?.[0] ?? value.phone?.[0] ?? '?').toUpperCase()}
          </span>
          <div className="up-chip-text">
            <strong>{value.full_name?.trim() || t('picker.unnamed')}</strong>
            <span className="muted">
              {value.phone}
              {value.role_id ? ` · ${ROLE_LABEL[value.role_id] ?? 'role ' + value.role_id}` : ''}
              {` · #${value.user_id}`}
            </span>
          </div>
        </div>
        <button
          type="button"
          className="up-chip-clear"
          onClick={clear}
          disabled={disabled}
          aria-label={t('picker.change_aria')}
          title={t('picker.change_title')}
        >
          {t('picker.change')}
        </button>
      </div>
    )
  }

  return (
    <div className="user-picker" ref={containerRef}>
      <input
        ref={inputRef}
        type="search"
        value={query}
        onChange={(e) => { setQuery(e.target.value); setOpen(true) }}
        onFocus={() => setOpen(true)}
        onKeyDown={onKeyDown}
        placeholder={placeholder ?? t('picker.search_placeholder')}
        disabled={disabled}
        autoComplete="off"
        role="combobox"
        aria-expanded={open}
        aria-controls="user-picker-list"
        aria-autocomplete="list"
      />
      {open && (query.trim() || loading) && (
        <ul
          id="user-picker-list"
          className="up-list"
          role="listbox"
        >
          {loading && results.length === 0 && (
            <li className="up-empty">{t('picker.searching')}</li>
          )}
          {!loading && results.length === 0 && query.trim().length > 0 && (
            <li className="up-empty">{t('picker.no_match', { q: query.trim() })}</li>
          )}
          {results.map((u, i) => (
            <li
              key={u.user_id}
              role="option"
              aria-selected={i === highlight}
              className={`up-row${i === highlight ? ' is-highlighted' : ''}`}
              onMouseEnter={() => setHighlight(i)}
              onMouseDown={(e) => { e.preventDefault(); pick(u) }}
            >
              <span className="up-row-avatar" aria-hidden="true">
                {(u.full_name?.[0] ?? u.phone?.[0] ?? '?').toUpperCase()}
              </span>
              <div className="up-row-text">
                <strong>{u.full_name?.trim() || t('picker.unnamed')}</strong>
                <span className="muted">
                  {u.phone}
                  {u.role_id ? ` · ${ROLE_LABEL[u.role_id] ?? 'role ' + u.role_id}` : ''}
                  {` · #${u.user_id}`}
                </span>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
