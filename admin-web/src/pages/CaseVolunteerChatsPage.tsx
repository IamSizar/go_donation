/**
 * Admin Case↔Volunteer Chats page (Note #36, part 3) — oversight of every
 * Staff↔Volunteer↔Beneficiary chat. Unlike the marriage chat, identities are
 * NOT masked here (operational coordination, not a sensitive introduction),
 * so this page shows real names on both sides. Admins can claim a thread to
 * become the named "Responsible Staff Member" (same pattern as the donor↔
 * beneficiary Messages page).
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import ExportCsvButton from '../components/ExportCsvButton'
import { type CsvColumn } from '../lib/csv'

type AdminThread = {
  id: number
  case_id: number
  case_code: string
  case_title: string
  volunteer_user_id: number
  volunteer_name: string | null
  volunteer_phone: string | null
  beneficiary_user_id: number
  beneficiary_name: string | null
  beneficiary_phone: string | null
  assigned_staff_user_id: number | null
  assigned_staff_name: string | null
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
  sender_role: 'volunteer' | 'beneficiary' | 'staff'
  sender_name: string | null
  body: string
  created_at: string
}

function name(n: string | null, id: number, t: (key: string, vars?: Record<string, string | number>) => string): string {
  return n && n.trim() ? n : t('common.user_ref', { id })
}

const THREAD_CSV_COLUMNS: CsvColumn<AdminThread>[] = [
  { header: 'id', get: (t) => t.id },
  { header: 'case_code', get: (t) => t.case_code },
  { header: 'volunteer_user_id', get: (t) => t.volunteer_user_id },
  { header: 'volunteer_name', get: (t) => t.volunteer_name ?? '' },
  { header: 'volunteer_phone', get: (t) => t.volunteer_phone ?? '' },
  { header: 'beneficiary_user_id', get: (t) => t.beneficiary_user_id },
  { header: 'beneficiary_name', get: (t) => t.beneficiary_name ?? '' },
  { header: 'beneficiary_phone', get: (t) => t.beneficiary_phone ?? '' },
  { header: 'assigned_staff_name', get: (t) => t.assigned_staff_name ?? '' },
  { header: 'message_count', get: (t) => t.message_count },
  { header: 'last_message_at', get: (t) => t.last_message_at ?? '' },
  { header: 'created_at', get: (t) => t.created_at },
]

export default function CaseVolunteerChatsPage() {
  const { t } = useI18n()
  const [threads, setThreads] = useState<AdminThread[]>([])
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [q, setQ] = useState('')
  const [selected, setSelected] = useState<AdminThread | null>(null)
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [reply, setReply] = useState('')
  const [sending, setSending] = useState(false)
  const [claiming, setClaiming] = useState(false)
  const msgEnd = useRef<HTMLDivElement | null>(null)

  const loadThreads = useCallback(async () => {
    try {
      const res = await api.get<{ items: AdminThread[] }>('/api/admin/case-chats', {
        params: { q: q || undefined },
      })
      const items = res.data.items ?? []
      setThreads(items)
      setErr(null)
      return items
    } catch (e) {
      setErr(describeError(e))
      return null
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
      const res = await api.get<{ items: ChatMessage[] }>(`/api/admin/case-chats/${threadId}/messages`)
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
      await api.post(`/api/admin/case-chats/${selected.id}/messages`, { body: reply.trim() })
      setReply('')
      await loadMessages(selected.id)
    } catch (e) {
      setErr(describeError(e))
    } finally {
      setSending(false)
    }
  }

  async function claim() {
    if (!selected || claiming) return
    setClaiming(true)
    try {
      await api.post(`/api/admin/case-chats/${selected.id}/claim`)
      const items = await loadThreads()
      if (items) setSelected((s) => (s ? items.find((th) => th.id === s.id) ?? s : s))
    } catch (e) {
      setErr(describeError(e))
    } finally {
      setClaiming(false)
    }
  }

  async function release() {
    if (!selected || claiming) return
    setClaiming(true)
    try {
      await api.post(`/api/admin/case-chats/${selected.id}/release`)
      const items = await loadThreads()
      if (items) setSelected((s) => (s ? items.find((th) => th.id === s.id) ?? s : s))
    } catch (e) {
      setErr(describeError(e))
    } finally {
      setClaiming(false)
    }
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1 style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ fontSize: '1.3rem' }}>🤝</span>
            {t('nav.case_volunteer_chats')}
          </h1>
          <p className="muted">{t('page.case_volunteer_chats.subtitle')}</p>
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
            filenameBase="case_volunteer_chats"
            title={t('nav.case_volunteer_chats')}
            module="volunteers"
          />
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}

      <div style={{ display: 'grid', gridTemplateColumns: '340px 1fr', gap: 16, alignItems: 'start' }}>
        <div className="card" style={{ padding: 8, maxHeight: '70vh', overflowY: 'auto' }}>
          {loading && threads.length === 0 && <p className="muted" style={{ padding: 12 }}>{t('common.loading')}</p>}
          {!loading && threads.length === 0 && (
            <p className="muted" style={{ padding: 12 }}>{t('page.case_volunteer_chats.empty')}</p>
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
                    {name(th.volunteer_name, th.volunteer_user_id, t)} ↔ {name(th.beneficiary_name, th.beneficiary_user_id, t)}
                  </strong>
                </div>
                <span className="muted" style={{ fontSize: 12, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {th.last_message ?? th.case_code}
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
                <strong>
                  {name(selected.volunteer_name, selected.volunteer_user_id, t)} {t('page.case_volunteer_chats.volunteer_paren')}
                  {' ↔ '}
                  {name(selected.beneficiary_name, selected.beneficiary_user_id, t)} {t('page.case_volunteer_chats.beneficiary_paren')}
                </strong>
                <div>
                  <span className="muted" style={{ fontSize: 12.5 }}>{t('col.profile_code')}: {selected.case_code} — {selected.case_title}</span>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6 }}>
                  {selected.assigned_staff_user_id ? (
                    <>
                      <span className="muted" style={{ fontSize: 12.5 }}>
                        {t('common.msg_assigned_to')}: <strong>{name(selected.assigned_staff_name, selected.assigned_staff_user_id, t)}</strong>
                      </span>
                      <button className="secondary" style={{ padding: '2px 10px', fontSize: 12 }} onClick={release} disabled={claiming}>
                        {t('common.msg_release')}
                      </button>
                    </>
                  ) : (
                    <button className="secondary" style={{ padding: '2px 10px', fontSize: 12 }} onClick={claim} disabled={claiming}>
                      {t('common.msg_claim')}
                    </button>
                  )}
                </div>
              </div>

              <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 10, paddingRight: 4 }}>
                {messages.length === 0 && <p className="muted" style={{ margin: 'auto' }}>{t('common.msg_no_messages')}</p>}
                {messages.map((m) => {
                  const isStaff = m.sender_role === 'staff'
                  const isBeneficiary = m.sender_role === 'beneficiary'
                  const align = isStaff ? 'center' : isBeneficiary ? 'flex-end' : 'flex-start'
                  const bg = isStaff
                    ? 'rgba(96,125,139,0.18)'
                    : isBeneficiary
                    ? 'color-mix(in srgb, var(--color-primary, #1B37C9) 16%, transparent)'
                    : 'var(--color-surface-2, rgba(127,127,127,0.10))'
                  return (
                    <div key={m.id} style={{ alignSelf: align, maxWidth: '72%' }}>
                      <div className="muted" style={{ fontSize: 11, marginBottom: 2, textAlign: isBeneficiary ? 'right' : 'left' }}>
                        {isStaff ? `🛡 ${m.sender_name ?? t('nav.support')}` : m.sender_name ?? t('common.user_ref', { id: m.sender_user_id })}
                      </div>
                      <div style={{ background: bg, padding: '8px 12px', borderRadius: 12, fontSize: 14, lineHeight: 1.4 }}>
                        {m.body}
                      </div>
                      <div className="muted" style={{ fontSize: 10, marginTop: 2, textAlign: isBeneficiary ? 'right' : 'left' }}>
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
                  placeholder={t('common.msg_reply')}
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
