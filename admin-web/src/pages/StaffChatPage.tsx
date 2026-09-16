/**
 * Staff Chat page (Note #36, part 2) — internal "Operational Administrative
 * Chat": direct messaging between any two dashboard accounts (Manager ↔
 * Staff Member, or any other staff pair). Never reachable by app users —
 * these routes require a valid dashboard session and are open to every
 * staff tier, not gated by a business-module permission.
 *
 * EXPORT (OPOS #26397). The open conversation exports the messages already on
 * screen and never fetches them again, because this page's messages route
 * marks the thread read. It still exports the LATEST of them: the rows are
 * read when the export runs, after the PIN, not when the button rendered.
 * StaffConversationExport below has the details.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useAuth } from '../lib/auth'
import { chatExportColumns, chatExportFilenameBase, chatExportTitle, staffExportRows } from '../lib/chatExport'
import { useI18n, useStatusLabel } from '../lib/i18n'
import ExportCsvButton from '../components/ExportCsvButton'
import PageHead from '../components/PageHead'
import ChatLifecycleControls from '../components/ChatLifecycleControls'

/** Columns of the one-conversation export (OPOS #26397). */
const CONVERSATION_EXPORT_COLUMNS = chatExportColumns()

/**
 * The open staff conversation's export button, gated by messages export (D5).
 *
 * NO RE-FETCH. It exports the messages this page already holds instead of
 * loading them again. GET /api/admin/staff-chats/:id/messages marks the thread
 * read for the caller (handlers/staff_chat.go Messages → staffchat.Store.MarkRead),
 * and the page already sends it when the thread opens and every 3 s after, so
 * the export itself changes no read state.
 *
 * BUT THE LATEST ROWS. The rows are read when the export runs, after the PIN,
 * not when the button rendered. Typing a PIN takes a while and the poll keeps
 * landing meanwhile, so a copy taken at render time would silently leave out
 * every message that arrived during the PIN. `latestMessages` always holds the
 * page's newest list.
 *
 * ONE THREAD ONLY. Rows are filtered to the thread that was open when the
 * operator clicked Export, because a load for the previously selected thread
 * can land after a switch and replace the list. Nothing is offered while the
 * list holds none of this thread's messages: a file of nothing, or of another
 * thread's rows, would mislead.
 */
function StaffConversationExport({ thread, messages }: { thread: StaffThread; messages: StaffMessage[] }) {
  const { t } = useI18n()
  const { user } = useAuth()
  const latestMessages = useRef(messages)
  useEffect(() => {
    latestMessages.current = messages
  }, [messages])
  if (!user || !messages.some((m) => m.thread_id === thread.id)) return null
  const threadId = thread.id
  // Staff chat has no sender role; each sender's tier stands in for one.
  const parties = [
    { user_id: thread.other_user_id, staff_tier: thread.other_staff_tier },
    { user_id: user.user_id, staff_tier: user.staff_tier },
  ]
  // Runs after the PIN; reads the newest list, never this render's copy.
  const loadRows = async () =>
    staffExportRows(latestMessages.current.filter((m) => m.thread_id === threadId), parties)
  return (
    <ExportCsvButton
      loadRows={loadRows}
      columns={CONVERSATION_EXPORT_COLUMNS}
      filenameBase={chatExportFilenameBase('staff', thread.id)}
      title={chatExportTitle('staff', thread.id)}
      module="messages"
      label={t('export.conversation')}
    />
  )
}

type StaffThread = {
  id: number
  other_user_id: number
  other_name: string | null
  other_staff_tier: string | null
  last_message: string | null
  last_message_at: string | null
  unread_count: number
  updated_at: string
  // Migration 117 — the staff-controlled lifecycle, driving the moderation
  // strip below the conversation header.
  lifecycle?: 'open' | 'paused' | 'ended'
  lifecycle_reason?: string | null
  is_archived?: boolean
}

type StaffMessage = {
  id: number
  thread_id: number
  sender_user_id: number
  sender_name: string | null
  body: string
  created_at: string
}

type DirectoryEntry = {
  user_id: number
  full_name: string | null
  phone: string
  staff_tier: string
}

function name(n: string | null, id: number): string {
  return n && n.trim() ? n : `#${id}`
}

export default function StaffChatPage() {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const [threads, setThreads] = useState<StaffThread[]>([])
  // The "loading" line only ever shows before the first thread list arrives
  // (it is rendered as `loading && threads.length === 0`), so it is derived
  // from that rather than set at the top of the polling effect. The 5s poll
  // refreshes in place and never brings the line back.
  const [threadsLoaded, setThreadsLoaded] = useState(false)
  const loading = !threadsLoaded
  const [err, setErr] = useState<string | null>(null)
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [messages, setMessages] = useState<StaffMessage[]>([])
  const [reply, setReply] = useState('')
  const [sending, setSending] = useState(false)
  const [directory, setDirectory] = useState<DirectoryEntry[]>([])
  const [pickerOpen, setPickerOpen] = useState(false)
  const msgEnd = useRef<HTMLDivElement | null>(null)

  const selected = threads.find((th) => th.id === selectedId) ?? null

  const loadThreads = useCallback(async () => {
    try {
      const res = await api.get<{ items: StaffThread[] }>('/api/admin/staff-chats', {
        params: { include_archived: '1' },
      })
      setThreads(res.data.items ?? [])
      setErr(null)
    } catch (e) {
      setErr(describeError(e))
    }
  }, [])

  useEffect(() => {
    // `loadThreads` only calls setState after awaiting the request, so nothing
    // here is synchronous and no cascading render happens. The rule reports it
    // anyway because it steps into a useCallback without modelling the await.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadThreads().finally(() => setThreadsLoaded(true))
    const id = setInterval(loadThreads, 5000)
    return () => clearInterval(id)
  }, [loadThreads])

  const loadMessages = useCallback(async (threadId: number) => {
    try {
      const res = await api.get<{ items: StaffMessage[] }>(`/api/admin/staff-chats/${threadId}/messages`)
      setMessages(res.data.items ?? [])
    } catch {
      /* keep previous on transient error */
    }
  }, [])

  useEffect(() => {
    if (!selectedId) return
    // `loadMessages` only calls setState after awaiting the request, so
    // nothing here is synchronous and no cascading render happens. The rule
    // reports it anyway because it steps into a useCallback without modelling
    // the await.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadMessages(selectedId)
    const id = setInterval(() => loadMessages(selectedId), 3000)
    return () => clearInterval(id)
  }, [selectedId, loadMessages])

  useEffect(() => {
    msgEnd.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  async function openPicker() {
    setPickerOpen(true)
    try {
      const res = await api.get<{ items: DirectoryEntry[] }>('/api/admin/staff-directory')
      setDirectory(res.data.items ?? [])
    } catch (e) {
      setErr(describeError(e))
    }
  }

  async function startChat(userId: number) {
    try {
      const res = await api.post<{ thread_id: number }>('/api/admin/staff-chats/start', { user_id: userId })
      setPickerOpen(false)
      await loadThreads()
      setSelectedId(res.data.thread_id)
    } catch (e) {
      setErr(describeError(e))
    }
  }

  async function sendReply() {
    if (!selectedId || !reply.trim() || sending) return
    setSending(true)
    try {
      await api.post(`/api/admin/staff-chats/${selectedId}/messages`, { body: reply.trim() })
      setReply('')
      await loadMessages(selectedId)
      await loadThreads()
    } catch (e) {
      setErr(describeError(e))
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1 style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ fontSize: '1.3rem' }}>🗨️</span>
            {t('nav.staff_chat')}
          </h1>
          <p className="muted">{t('page.staff_chat.subtitle')}</p>
        </div>
        <div className="row">
          <button onClick={openPicker}>{t('page.staff_chat.new')}</button>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}

      {pickerOpen && (
        <div className="card" style={{ padding: 12 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
            <strong>{t('page.staff_chat.pick_someone')}</strong>
            <button className="secondary" onClick={() => setPickerOpen(false)}>{t('common.cancel')}</button>
          </div>
          {directory.length === 0 ? (
            <p className="muted">{t('common.loading')}</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              {directory.map((d) => (
                <button
                  key={d.user_id}
                  onClick={() => startChat(d.user_id)}
                  style={{ textAlign: 'start', border: 'none', cursor: 'pointer', padding: '8px 10px', borderRadius: 8 }}
                >
                  <strong>{name(d.full_name, d.user_id)}</strong>{' '}
                  {/* staff_tier is a backend enum (super_admin / supervisor /
                      employee), and it was printed verbatim — so the staff
                      picker offered "· super_admin ·" on a screen that is
                      otherwise fully Arabic. status.super_admin,
                      status.supervisor and status.employee already existed in
                      all four locales; this line simply never asked for
                      them. */}
                  <span className="muted" style={{ fontSize: 12 }}>· {statusLabel(d.staff_tier)} · {d.phone}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      <div style={{ display: 'grid', gridTemplateColumns: '340px 1fr', gap: 16, alignItems: 'start' }}>
        <div className="card" style={{ padding: 8, maxHeight: '70vh', overflowY: 'auto' }}>
          {loading && threads.length === 0 && <p className="muted" style={{ padding: 12 }}>{t('common.loading')}</p>}
          {!loading && threads.length === 0 && (
            <p className="muted" style={{ padding: 12 }}>{t('page.staff_chat.empty')}</p>
          )}
          {threads.map((th) => {
            const active = selectedId === th.id
            return (
              <button
                key={th.id}
                onClick={() => { setSelectedId(th.id); setMessages([]) }}
                style={{
                  width: '100%', textAlign: 'start', border: 'none', cursor: 'pointer',
                  padding: '11px 12px', borderRadius: 12, marginBottom: 4,
                  background: active ? 'color-mix(in srgb, var(--color-primary, #1B37C9) 12%, transparent)' : 'transparent',
                  display: 'flex', flexDirection: 'column', gap: 4,
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
                  <strong style={{ fontSize: 13.5 }}>{name(th.other_name, th.other_user_id)}</strong>
                  {th.unread_count > 0 && <span className="badge tone-warning">{th.unread_count}</span>}
                </div>
                <span className="muted" style={{ fontSize: 12, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {th.last_message ?? th.other_staff_tier ?? ''}
                </span>
              </button>
            )
          })}
        </div>

        <div className="card" style={{ display: 'flex', flexDirection: 'column', minHeight: '70vh', maxHeight: '70vh' }}>
          {!selected ? (
            <div className="muted" style={{ margin: 'auto', textAlign: 'center' }}>
              {t('common.msg_select_convo')}
            </div>
          ) : (
            <>
              <div style={{ borderBottom: '1px solid var(--color-border, rgba(127,127,127,0.18))', paddingBottom: 10, marginBottom: 10 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
                  <div>
                    <strong>{name(selected.other_name, selected.other_user_id)}</strong>{' '}
                    <span className="muted" style={{ fontSize: 12.5 }}>· {selected.other_staff_tier}</span>
                  </div>
                  <StaffConversationExport thread={selected} messages={messages} />
                </div>
                {/* Chat lifecycle (migration 117) — end / pause / resume /
                    archive / delete, staff only. */}
                <div style={{ marginTop: 8 }}>
                  <ChatLifecycleControls
                    basePath={`/api/admin/staff-chats/${selected.id}`}
                    deleteModule="messages"
                    thread={selected}
                    onChanged={loadThreads}
                  />
                </div>
              </div>

              <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 10, paddingInlineEnd: 4 }}>
                {messages.length === 0 && <p className="muted" style={{ margin: 'auto' }}>{t('common.msg_no_messages')}</p>}
                {messages.map((m) => {
                  const mine = m.sender_user_id !== selected.other_user_id
                  const align = mine ? 'flex-end' : 'flex-start'
                  const bg = mine
                    ? 'color-mix(in srgb, var(--color-primary, #1B37C9) 16%, transparent)'
                    : 'var(--color-surface-2, rgba(127,127,127,0.10))'
                  return (
                    <div key={m.id} style={{ alignSelf: align, maxWidth: '72%' }}>
                      <div className="muted" style={{ fontSize: 11, marginBottom: 2, textAlign: mine ? 'end' : 'start' }}>
                        {m.sender_name ?? `#${m.sender_user_id}`}
                      </div>
                      <div style={{ background: bg, padding: '8px 12px', borderRadius: 12, fontSize: 14, lineHeight: 1.4 }}>
                        {m.body}
                      </div>
                      <div className="muted" style={{ fontSize: 10, marginTop: 2, textAlign: mine ? 'end' : 'start' }}>
                        {new Date(m.created_at).toLocaleString()}
                      </div>
                    </div>
                  )
                })}
                <div ref={msgEnd} />
              </div>

              <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
                <input
                  value={reply}
                  onChange={(e) => setReply(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter') sendReply() }}
                  placeholder={t('common.msg_reply_plain')}
                  style={{ flex: 1 }}
                  disabled={sending}
                />
                <button onClick={sendReply} disabled={sending || !reply.trim()}>
                  {sending ? t('common.msg_sending') : t('common.msg_send')}
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
