/**
 * Staff Chat page (Note #36, part 2) — internal "Operational Administrative
 * Chat": direct messaging between any two dashboard accounts (Manager ↔
 * Staff Member, or any other staff pair). Never reachable by app users —
 * these routes require a valid dashboard session and are open to every
 * staff tier, not gated by a business-module permission.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'

type StaffThread = {
  id: number
  other_user_id: number
  other_name: string | null
  other_staff_tier: string | null
  last_message: string | null
  last_message_at: string | null
  unread_count: number
  updated_at: string
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
  const [threads, setThreads] = useState<StaffThread[]>([])
  const [loading, setLoading] = useState(false)
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
      const res = await api.get<{ items: StaffThread[] }>('/api/admin/staff-chats')
      setThreads(res.data.items ?? [])
      setErr(null)
    } catch (e) {
      setErr(describeError(e))
    }
  }, [])

  useEffect(() => {
    setLoading(true)
    loadThreads().finally(() => setLoading(false))
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
      <div className="page-head">
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
      </div>

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
                  style={{ textAlign: 'left', border: 'none', cursor: 'pointer', padding: '8px 10px', borderRadius: 8 }}
                >
                  <strong>{name(d.full_name, d.user_id)}</strong>{' '}
                  <span className="muted" style={{ fontSize: 12 }}>· {d.staff_tier} · {d.phone}</span>
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
                  width: '100%', textAlign: 'left', border: 'none', cursor: 'pointer',
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
                <strong>{name(selected.other_name, selected.other_user_id)}</strong>{' '}
                <span className="muted" style={{ fontSize: 12.5 }}>· {selected.other_staff_tier}</span>
              </div>

              <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 10, paddingRight: 4 }}>
                {messages.length === 0 && <p className="muted" style={{ margin: 'auto' }}>{t('common.msg_no_messages')}</p>}
                {messages.map((m) => {
                  const mine = m.sender_user_id !== selected.other_user_id
                  const align = mine ? 'flex-end' : 'flex-start'
                  const bg = mine
                    ? 'color-mix(in srgb, var(--color-primary, #1B37C9) 16%, transparent)'
                    : 'var(--color-surface-2, rgba(127,127,127,0.10))'
                  return (
                    <div key={m.id} style={{ alignSelf: align, maxWidth: '72%' }}>
                      <div className="muted" style={{ fontSize: 11, marginBottom: 2, textAlign: mine ? 'right' : 'left' }}>
                        {m.sender_name ?? `#${m.sender_user_id}`}
                      </div>
                      <div style={{ background: bg, padding: '8px 12px', borderRadius: 12, fontSize: 14, lineHeight: 1.4 }}>
                        {m.body}
                      </div>
                      <div className="muted" style={{ fontSize: 10, marginTop: 2, textAlign: mine ? 'right' : 'left' }}>
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
