// PostActivityPage — the "Activities" half of the Comments & Activities
// section (#10). A chronological feed of engagement across every post:
// comments as they're written and likes as they land.
//
// Comment moderation stays on its own page — this one answers a different
// question ("what's happening on the feed right now?") rather than "what
// needs my decision?", so it's read-only by design and links across to the
// post instead of duplicating the moderation controls.
// GET /api/admin/post-activity?kind=&limit=
import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Heart, MessageSquare } from 'lucide-react'
import { api, describeError } from '../lib/api'
import { useI18n, useStatusLabel } from '../lib/i18n'
import PageHead from '../components/PageHead'
import { fmtId } from '../lib/formatId'
import { formatDateTime } from '../lib/dates'

type Activity = {
  kind: 'comment' | 'like'
  id: number
  post_id: number
  post_title: string
  post_type: string
  user_id: number
  user_name: string
  body?: string
  status?: string
  flagged?: boolean
  created_at: string
}

const KINDS = ['all', 'comment', 'like'] as const

export default function PostActivityPage() {
  const { t } = useI18n()
  // post_type and the comment status arrive as machine values; render them
  // through the shared resolver so they are not the one English word left on
  // an otherwise translated page.
  const label = useStatusLabel()
  const [items, setItems] = useState<Activity[]>([])
  const [kind, setKind] = useState<(typeof KINDS)[number]>('all')
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)

  const load = useCallback(() => {
    setLoading(true)
    api
      .get<{ items: Activity[] }>('/api/admin/post-activity', {
        params: { kind: kind === 'all' ? undefined : kind, limit: 200 },
      })
      .then((res) => {
        setItems(res.data.items ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }, [kind])
  useEffect(load, [load])

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('activity.title')}</h1>
          <p className="muted">{t('activity.subtitle')}</p>
        </div>
        <div className="row">
          {KINDS.map((k) => (
            <button
              key={k}
              type="button"
              className={k === kind ? '' : 'secondary'}
              onClick={() => setKind(k)}
            >
              {t(`activity.kind_${k}`)}
            </button>
          ))}
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}
      {!loading && items.length === 0 && <p className="muted">{t('activity.empty')}</p>}

      {!loading && items.length > 0 && (
        <div className="card stack activity-feed">
          {items.map((a) => (
            // A like has no id of its own, so the key falls back to the
            // (post, user, time) triple — unique because a like is a toggle
            // with one row per pair.
            <div className="activity-row" key={a.kind === 'comment' ? `c${a.id}` : `l${a.post_id}-${a.user_id}-${a.created_at}`}>
              <span className={`activity-icon tone-${a.kind === 'comment' ? 'info' : 'danger'}`} aria-hidden="true">
                {a.kind === 'comment' ? <MessageSquare size={14} /> : <Heart size={14} />}
              </span>
              <div className="activity-main">
                <p className="activity-line">
                  <strong>{a.user_name}</strong>{' '}
                  <span className="muted">
                    {a.kind === 'comment' ? t('activity.commented_on') : t('activity.liked')}
                  </span>{' '}
                  <Link to={`/detail/media/${a.post_id}`}>{a.post_title || fmtId(a.post_id)}</Link>
                  {a.post_type && <span className="badge tone-primary">{label(a.post_type)}</span>}
                </p>
                {a.kind === 'comment' && a.body && <p className="activity-body">{a.body}</p>}
                <p className="muted activity-meta">
                  {formatDateTime(a.created_at)} · {fmtId(a.user_id)}
                  {a.kind === 'comment' && a.status && a.status !== 'approved' && (
                    <>
                      {' '}
                      <span className="badge tone-warning">{label(a.status)}</span>
                    </>
                  )}
                  {a.flagged && (
                    <>
                      {' '}
                      <span className="badge tone-danger">{t('activity.flagged')}</span>
                    </>
                  )}
                </p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
