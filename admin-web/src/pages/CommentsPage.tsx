// CommentsPage — comment moderation queue for media posts (#25). Lists comments
// (pending first), lets an admin approve / hide each via a status dropdown, and
// delete. Flagged comments (matched a banned word) are badged.
// GET /api/admin/media-comments?status= · POST .../:id/status · DELETE .../:id
import { useCallback, useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type Comment = {
  id: number
  post_id: number
  user_id: number
  user_name: string
  post_title: string
  body: string
  status: string
  flagged: boolean
  created_at: string
}

const STATUSES = ['all', 'pending', 'approved', 'hidden']
const EDITABLE = ['pending', 'approved', 'hidden']

export default function CommentsPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Comment[]>([])
  const [status, setStatus] = useState('pending')
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)

  const load = useCallback(() => {
    setLoading(true)
    api
      .get<{ items: Comment[] }>('/api/admin/media-comments', {
        params: { status: status === 'all' ? undefined : status, limit: 200 },
      })
      .then((res) => {
        setItems(res.data.items ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }, [status])
  useEffect(load, [load])

  const setStatusFor = async (c: Comment, next: string) => {
    try {
      await api.post(`/api/admin/media-comments/${c.id}/status`, { status: next })
      toast.success(t('comments.status_saved'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const remove = async (id: number) => {
    if (!window.confirm(t('comments.confirm_delete'))) return
    try {
      await api.delete(`/api/admin/media-comments/${id}`)
      toast.success(t('comments.deleted'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('comments.title')}</h1>
          <p className="muted">{t('comments.subtitle')}</p>
        </div>
        <div className="row">
          <select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 'auto' }}>
            {STATUSES.map((s) => (
              <option key={s} value={s}>{t(`comments.status_${s}`)}</option>
            ))}
          </select>
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}
      {!loading && items.length === 0 && <p className="muted">{t('comments.empty')}</p>}

      {!loading &&
        items.map((c) => (
          <div className="card" key={c.id}>
            <div className="page-head">
              <div>
                <strong>{c.user_name || `User #${c.user_id}`}</strong>{' '}
                <span className="muted">· {t('comments.on_post')} #{c.post_id}{c.post_title ? ` — ${c.post_title}` : ''}</span>
                {c.flagged && <span className="badge danger" style={{ marginInlineStart: 8 }}>{t('comments.flagged')}</span>}
              </div>
              <span className="muted">{c.created_at?.slice(0, 10)}</span>
            </div>
            <p style={{ whiteSpace: 'pre-wrap', margin: '8px 0' }}>{c.body}</p>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <span className="muted">{t('comments.status')}:</span>
              <select value={c.status} onChange={(e) => setStatusFor(c, e.target.value)} style={{ width: 'auto' }}>
                {EDITABLE.map((s) => (
                  <option key={s} value={s}>{t(`comments.status_${s}`)}</option>
                ))}
              </select>
              <button className="btn danger" onClick={() => remove(c.id)}>{t('common.delete')}</button>
            </div>
          </div>
        ))}
    </div>
  )
}
