/**
 * Admin Marriage Chats page — oversight of every staff-mediated marriage
 * chat (Note #35). Same layout/polling pattern as MessagesPage.tsx, but the
 * two non-staff parties (requester / profile owner) never see each other's
 * real identity — only staff does, which is exactly what this page shows.
 * Admin replies are tagged sender_role="staff".
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n, useStatusLabel } from '../lib/i18n'
import ExportCsvButton from '../components/ExportCsvButton'
import { type CsvColumn } from '../lib/csv'

type AdminThread = {
  id: number
  status: string
  profile_id: number
  profile_code: string
  requester_user_id: number
  requester_name: string | null
  requester_phone: string | null
  owner_user_id: number
  owner_name: string | null
  owner_phone: string | null
  message_count: number
  last_message: string | null
  last_message_at: string | null
  created_at: string
  updated_at: string
}

type ChatMessage = {
  id: number
  thread_id: number
  sender_user_id: number
  sender_role: 'requester' | 'owner' | 'staff'
  sender_name: string | null
  body: string
  created_at: string
}

function name(
  n: string | null,
  id: number,
  t: (key: string, vars?: Record<string, string | number>) => string,
): string {
  return n && n.trim() ? n : t('common.user_ref', { id })
}

const THREAD_CSV_COLUMNS: CsvColumn<AdminThread>[] = [
  { header: 'id', get: (t) => t.id },
  { header: 'status', get: (t) => t.status },
  { header: 'profile_id', get: (t) => t.profile_id },
  { header: 'profile_code', get: (t) => t.profile_code },
  { header: 'requester_user_id', get: (t) => t.requester_user_id },
  { header: 'requester_name', get: (t) => t.requester_name ?? '' },
  { header: 'requester_phone', get: (t) => t.requester_phone ?? '' },
  { header: 'owner_user_id', get: (t) => t.owner_user_id },
  { header: 'owner_name', get: (t) => t.owner_name ?? '' },
  { header: 'owner_phone', get: (t) => t.owner_phone ?? '' },
  { header: 'message_count', get: (t) => t.message_count },
  { header: 'last_message', get: (t) => t.last_message ?? '' },
  { header: 'last_message_at', get: (t) => t.last_message_at ?? '' },
  { header: 'created_at', get: (t) => t.created_at },
]

function StatusBadge({ status }: { status: string }) {
  const statusLabel = useStatusLabel()
  const tone = status === 'active' ? 'success' : status === 'pending' ? 'warning' : 'info'
  return <span className={`badge tone-${tone}`}>{statusLabel(status)}</span>
}

export default function MarriageChatsPage() {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const [threads, setThreads] = useState<AdminThread[]>([])
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [q, setQ] = useState('')
  const [selected, setSelected] = useState<AdminThread | null>(null)
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [reply, setReply] = useState('')
  const [sending, setSending] = useState(false)
  const msgEnd = useRef<HTMLDivElement | null>(null)

  const loadThreads = useCallback(async () => {
    try {
      const res = await api.get<{ items: AdminThread[] }>('/api/admin/marriage/chats', {
        params: { q: q || undefined },
      })
      setThreads(res.data.items ?? [])
      setErr(null)
    } catch (e) {
      setErr(describeError(e))
    }
  }, [q])

  useEffect(() => {
    setLoading(true)
    loadThreads().finally(() => setLoading(false))
    const id = setInterval(loadThreads, 5000)
    return () => clearInterval(id)
  }, [loadThreads])

  const loadMessages = useCallback(async (threadId: number) => {
    try {
      const res = await api.get<{ items: ChatMessage[] }>(`/api/admin/marriage/chats/${threadId}/messages`)
      setMessages(res.data.items ?? [])
    } catch {
      /* keep previous on transient error */
    }
  }, [])

  useEffect(() => {
    if (!selected) return
    loadMessages(selected.id)
    const id = setInterval(() => loadMessages(selected.id), 3000)
    return () => clearInterval(id)
  }, [selected, loadMessages])

  useEffect(() => {
    msgEnd.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  async function sendReply() {
    if (!selected || !reply.trim() || sending) return
    setSending(true)
    try {
      await api.post(`/api/admin/marriage/chats/${selected.id}/messages`, { body: reply.trim() })
      setReply('')
      await loadMessages(selected.id)
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
            <span style={{ fontSize: '1.3rem' }}>💬</span>
            {t('nav.marriage_chats')}
          </h1>
          <p className="muted">{t('common.msg_convos_count', { n: threads.length })}</p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t('common.msg_search')}
            style={{ width: 240 }}
          />
          <ExportCsvButton
            rows={threads}
            columns={THREAD_CSV_COLUMNS}
            filenameBase="marriage_chats"
            title={t('nav.marriage_chats')}
            module="marriage"
          />
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}

      <div style={{ display: 'grid', gridTemplateColumns: '340px 1fr', gap: 16, alignItems: 'start' }}>
        <div className="card" style={{ padding: 8, maxHeight: '70vh', overflowY: 'auto' }}>
          {loading && threads.length === 0 && <p className="muted" style={{ padding: 12 }}>{t('common.loading')}</p>}
          {!loading && threads.length === 0 && (
            <p className="muted" style={{ padding: 12 }}>{t('common.msg_no_convos')}</p>
          )}
          {threads.map((th) => {
            const active = selected?.id === th.id
            return (
              <button
                key={th.id}
                onClick={() => { setSelected(th); setMessages([]) }}
                style={{
                  width: '100%', textAlign: 'left', border: 'none', cursor: 'pointer',
                  padding: '11px 12px', borderRadius: 12, marginBottom: 4,
                  background: active ? 'color-mix(in srgb, var(--color-primary, #1B37C9) 12%, transparent)' : 'transparent',
                  display: 'flex', flexDirection: 'column', gap: 4,
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
                  <strong style={{ fontSize: 13.5 }}>
                    {name(th.requester_name, th.requester_user_id, t)} ↔ {name(th.owner_name, th.owner_user_id, t)}
                  </strong>
                  <StatusBadge status={th.status} />
                </div>
                <span className="muted" style={{ fontSize: 12, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {th.last_message ?? th.profile_code}
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
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <strong>
                    {name(selected.requester_name, selected.requester_user_id, t)} {t('common.msg_requester_paren')} ↔ {name(selected.owner_name, selected.owner_user_id, t)} {t('common.owner_paren')}
                  </strong>
                  <StatusBadge status={selected.status} />
                </div>
                <span className="muted" style={{ fontSize: 12.5 }}>{t('col.profile_code')}: {selected.profile_code}</span>
              </div>

              <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 10, paddingRight: 4 }}>
                {messages.length === 0 && <p className="muted" style={{ margin: 'auto' }}>{t('common.msg_no_messages')}</p>}
                {messages.map((m) => {
                  const isStaff = m.sender_role === 'staff'
                  const isOwner = m.sender_role === 'owner'
                  const align = isStaff ? 'center' : isOwner ? 'flex-end' : 'flex-start'
                  const bg = isStaff
                    ? 'rgba(96,125,139,0.18)'
                    : isOwner
                    ? 'color-mix(in srgb, var(--color-primary, #1B37C9) 16%, transparent)'
                    : 'var(--color-surface-2, rgba(127,127,127,0.10))'
                  const roleLabel = isStaff
                    ? `🛡 ${t('nav.support')}`
                    : isOwner
                    ? (m.sender_name ?? t('common.msg_owner_paren'))
                    : (m.sender_name ?? t('common.msg_requester_paren'))
                  return (
                    <div key={m.id} style={{ alignSelf: align, maxWidth: '72%' }}>
                      <div className="muted" style={{ fontSize: 11, marginBottom: 2, textAlign: isOwner ? 'right' : 'left' }}>
                        {roleLabel}
                      </div>
                      <div style={{ background: bg, padding: '8px 12px', borderRadius: 12, fontSize: 14, lineHeight: 1.4 }}>
                        {m.body}
                      </div>
                      <div className="muted" style={{ fontSize: 10, marginTop: 2, textAlign: isOwner ? 'right' : 'left' }}>
                        {new Date(m.created_at).toLocaleString()}
                      </div>
                    </div>
                  )
                })}
                <div ref={msgEnd} />
              </div>

              {selected.status === 'active' ? (
                <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
                  <input
                    value={reply}
                    onChange={(e) => setReply(e.target.value)}
                    onKeyDown={(e) => { if (e.key === 'Enter') sendReply() }}
                    placeholder={t('common.msg_reply')}
                    style={{ flex: 1 }}
                    disabled={sending}
                  />
                  <button onClick={sendReply} disabled={sending || !reply.trim()}>
                    {sending ? t('common.msg_sending') : t('common.msg_send')}
                  </button>
                </div>
              ) : (
                <div className="muted" style={{ marginTop: 10, fontSize: 13 }}>
                  {t('common.msg_chat_inactive', { status: statusLabel(selected.status) })}
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}
