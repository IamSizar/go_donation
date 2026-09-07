/**
 * ContactBlocksPanel — the refused contact-sharing attempts on ONE thread.
 *
 * WHY THIS EXISTS
 * K19 has two halves and only one of them had a screen. The BLOCK works: a
 * message in the supervised donor ↔ owner thread carrying a phone number or an
 * email address is refused before it is stored, because every new message fans
 * out an 80-character push preview — a number that reached the database would
 * already have left the server. Each refusal is recorded in
 * `chat_contact_blocks` (migration 116).
 *
 * The MONITOR half was never built. The endpoint has existed and been tested
 * since 116, and nothing under admin-web/src fetched it, so the record the log
 * exists to produce was invisible to every staff member. The handler's own
 * comment says it plainly: one refused message is a misunderstanding, the same
 * sender refused repeatedly is the pattern worth acting on, "and it is only
 * visible if someone can see the list".
 *
 * WHAT IT DELIBERATELY CANNOT DO
 * There is no "reveal" control, because there is nothing to reveal. Bodies are
 * redacted at the point of capture — the raw number was never stored, so this
 * panel cannot leak one. That is a property of migration 116 rather than a
 * restriction imposed here, and it is why the redacted body is safe to print
 * in full.
 *
 * STYLING: existing utilities only (`card`, `stack`, `muted`, `error-box`,
 * `badge tone-*`), the same set ChatLifecycleControls draws on. A bespoke
 * class vocabulary here would be a second system to keep in sync, and any new
 * custom property would have to answer to scripts/check-css-tokens.mjs.
 *
 * All four async states are covered: a line while loading, the list as
 * content, a friendly reason plus retry on failure, and a reassuring "nothing
 * was blocked" when the thread is clean — an empty log is the GOOD outcome
 * here and must not read like a fault.
 */
import { useCallback, useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'

/** What a message was refused for. Mirrors the CHECK in migration 116. */
export type ContactBlockKind = 'phone' | 'email' | 'both'

/** One refused attempt, as `ListContactBlocks` returns it (newest first). */
export type ContactBlock = {
  id: number
  thread_id: number
  sender_user_id: number
  sender_name: string | null
  kind: ContactBlockKind
  match_count: number
  /** The message with every contact detail already replaced by "•••". */
  redacted_body: string
  created_at: string
}

/**
 * Both kinds are the same refusal; `both` is the stronger signal because the
 * sender reached for two channels in one message.
 */
const KIND_TONE: Record<ContactBlockKind, string> = {
  phone: 'tone-warning',
  email: 'tone-warning',
  both: 'tone-danger',
}

export default function ContactBlocksPanel({ threadId }: { threadId: number }) {
  const { t } = useI18n()
  const [items, setItems] = useState<ContactBlock[] | null>(null)
  const [error, setError] = useState('')

  /**
   * Fetches the list and settles BOTH pieces of state together.
   *
   * Nothing is set synchronously — an effect that calls setState before its
   * first await triggers a cascading render, which is what
   * react-hooks/set-state-in-effect exists to catch. Clearing the old error is
   * therefore folded into the same settle as the new result rather than run up
   * front, which also removes a flicker: the panel never blanks its error for
   * a moment before deciding whether the retry actually worked.
   *
   * [cancelled] guards the late response. The panel is remounted per thread by
   * its key, so this matters mainly for a retry racing an unmount.
   */
  const load = useCallback(
    async (isCancelled: () => boolean) => {
      try {
        const res = await api.get<{ items: ContactBlock[] }>(
          `/api/admin/chats/${threadId}/contact-blocks`,
        )
        if (isCancelled()) return
        setItems(res.data.items ?? [])
        setError('')
      } catch (e) {
        if (isCancelled()) return
        // Never swallowed: an operator who cannot tell "nothing was blocked"
        // from "the list failed to load" is worse off than one shown neither.
        setError(describeError(e))
        setItems(null)
      }
    },
    [threadId],
  )

  // Loads once per thread. Deliberately NOT polled, unlike the messages beside
  // it: a refusal is a supervision record to review, not a live feed, and a
  // second 3s timer on the same page would buy nothing.
  useEffect(() => {
    let cancelled = false
    void load(() => cancelled)
    return () => {
      cancelled = true
    }
  }, [load])

  return (
    <section className="card stack" aria-labelledby={`cb-h-${threadId}`}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
        <strong id={`cb-h-${threadId}`}>{t('contact_blocks.title')}</strong>
        {/* The COUNT is the signal — one row is noise, a run of them is the
            pattern this log was built to make visible. */}
        {items && items.length > 0 && (
          <span className="badge tone-warning">
            {t('contact_blocks.count', { count: items.length })}
          </span>
        )}
      </div>

      {error ? (
        <>
          <p className="error-box">{error}</p>
          <button type="button" className="secondary" onClick={() => void load(() => false)}>
            {t('common.retry')}
          </button>
        </>
      ) : items === null ? (
        <p className="muted">{t('contact_blocks.loading')}</p>
      ) : items.length === 0 ? (
        <p className="muted">{t('contact_blocks.none')}</p>
      ) : (
        <>
          <p className="muted">{t('contact_blocks.explain')}</p>
          <ul className="stack" style={{ listStyle: 'none', padding: 0, margin: 0 }}>
            {items.map((b) => (
              <li key={b.id} className="stack" style={{ gap: 4 }}>
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 8,
                    flexWrap: 'wrap',
                  }}
                >
                  <strong>
                    {b.sender_name ||
                      t('common.user_ref', { id: b.sender_user_id })}
                  </strong>
                  <span className={`badge ${KIND_TONE[b.kind]}`}>
                    {t(`contact_blocks.kind_${b.kind}`)}
                  </span>
                  <time className="muted" dateTime={b.created_at}>
                    {new Date(b.created_at).toLocaleString()}
                  </time>
                </div>
                {/* Safe to print in full: redacted at capture, never stored raw. */}
                <p className="muted" style={{ margin: 0 }}>
                  {b.redacted_body}
                </p>
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  )
}
