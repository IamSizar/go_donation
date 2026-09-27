// CommentsPage — moderation queue for every comment written in the app (#25).
//
// The app has THREE comment boxes, each with its own table and admin route:
//   media posts (News & Activities / Our Work / community events) → post_comments
//   donation campaigns                                             → campaign_comments
//   marriage (events) profile cards                                → marriage_profile_comments
// This page used to read only the first, and opened filtered to "pending"
// while almost every comment is saved "approved" — so on production it showed
// nothing at all, and campaign / marriage comments were visible nowhere in the
// dashboard. It now merges all three (pending first, then newest), defaults to
// every status, and sends each moderation action to its own source's route.
//
// Each source is fetched with its own module permission (media / campaigns /
// marriage). A source the operator may not view (403) is simply left out
// rather than failing the page.
import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import axios from 'axios'
import { api, describeError } from '../lib/api'
import { askToConfirm } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from '../components/PageHead'
import { fmtId } from '../lib/formatId'
import { formatDateTime } from '../lib/dates'
import { useHighlightedRow } from '../lib/useHighlightedRow'
import { HighlightBanner } from '../lib/HighlightBanner'

type Source = 'media' | 'campaign' | 'marriage'
const SOURCES: Source[] = ['media', 'campaign', 'marriage']
const SOURCE_FILTERS = ['all', ...SOURCES] as const
type SourceFilter = (typeof SOURCE_FILTERS)[number]

/** Where each source lives on the server, and where its target opens. */
const SOURCE_API: Record<Source, { base: string; detail: string; tone: string }> = {
  media:    { base: '/api/admin/media-comments',    detail: '/detail/media',     tone: 'tone-info' },
  campaign: { base: '/api/admin/campaign-comments', detail: '/detail/campaigns', tone: 'tone-success' },
  marriage: { base: '/api/admin/marriage-comments', detail: '/detail/marriage',  tone: 'tone-primary' },
}

/** The three routes' rows, which name their target differently. */
type RawComment = {
  id: number
  post_id?: number
  post_title?: string
  campaign_id?: number
  campaign_title?: string
  profile_id?: number
  user_id: number
  user_name: string
  body: string
  status: string
  flagged: boolean
  created_at: string
}

type Comment = {
  source: Source
  id: number
  targetId: number
  targetTitle: string
  user_id: number
  user_name: string
  body: string
  status: string
  flagged: boolean
  created_at: string
}

function normalize(source: Source, r: RawComment): Comment {
  const targetId = source === 'media' ? r.post_id : source === 'campaign' ? r.campaign_id : r.profile_id
  const targetTitle = source === 'media' ? r.post_title : source === 'campaign' ? r.campaign_title : ''
  return {
    source,
    id: r.id,
    targetId: targetId ?? 0,
    targetTitle: (targetTitle ?? '').trim(),
    user_id: r.user_id,
    user_name: r.user_name,
    body: r.body,
    status: r.status,
    flagged: r.flagged,
    created_at: r.created_at,
  }
}

const STATUSES = ['all', 'pending', 'approved', 'hidden']
const EDITABLE = ['pending', 'approved', 'hidden']

export default function CommentsPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [params, setParams] = useSearchParams()
  const rawSource = params.get('source')
  const source: SourceFilter = (SOURCE_FILTERS as readonly string[]).includes(rawSource ?? '')
    ? (rawSource as SourceFilter)
    : 'all'
  // The source lives in the URL so an alert link (/comments?source=campaign
  // &highlight=3) lands on the right list, and a refresh keeps it. Changing it
  // drops the highlight in the same update: comment ids are per-table, so #3
  // in one source is a different comment from #3 in another.
  const setSource = (next: SourceFilter) =>
    setParams((prev) => {
      const p = new URLSearchParams(prev)
      p.set('source', next)
      p.delete('highlight')
      return p
    }, { replace: true })

  const [status, setStatus] = useState('all')
  const [items, setItems] = useState<Comment[]>([])
  const [tick, setTick] = useState(0)
  const [loadedKey, setLoadedKey] = useState<string | null>(null)
  const reload = () => setTick((n) => n + 1)
  const [err, setErr] = useState<string | null>(null)
  const highlight = useHighlightedRow()

  const requestKey = `${source}|${status}|${tick}`
  const loading = loadedKey !== requestKey

  const load = useCallback(() => {
    const wanted = source === 'all' ? SOURCES : [source]
    Promise.allSettled(
      wanted.map((s) =>
        api
          .get<{ items: RawComment[] }>(SOURCE_API[s].base, {
            params: { status: status === 'all' ? undefined : status, limit: 500 },
          })
          .then((res) => (res.data.items ?? []).map((r) => normalize(s, r))),
      ),
    )
      .then((results) => {
        const merged: Comment[] = []
        let failure: unknown = null
        for (const r of results) {
          if (r.status === 'fulfilled') merged.push(...r.value)
          // No permission for that module: leave the source out quietly.
          else if (!(axios.isAxiosError(r.reason) && r.reason.response?.status === 403)) failure = r.reason
        }
        // Held (pending) comments first — they are the ones waiting on staff —
        // then newest first across all sources.
        merged.sort((a, b) =>
          Number(b.status === 'pending') - Number(a.status === 'pending') ||
          b.created_at.localeCompare(a.created_at))
        setItems(merged)
        setErr(failure ? describeError(failure) : null)
      })
      .finally(() => setLoadedKey(requestKey))
  }, [source, status, requestKey])
  useEffect(load, [load])

  const counts = useMemo(() => {
    const c: Record<string, number> = {}
    for (const x of items) c[x.source] = (c[x.source] ?? 0) + 1
    return c
  }, [items])

  const setStatusFor = async (c: Comment, next: string) => {
    try {
      await api.post(`${SOURCE_API[c.source].base}/${c.id}/status`, { status: next })
      toast.success(t('comments.status_saved'))
      reload()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const remove = async (c: Comment) => {
    if (!(await askToConfirm({ message: t('comments.confirm_delete'), destructive: true }))) return
    try {
      await api.delete(`${SOURCE_API[c.source].base}/${c.id}`)
      toast.success(t('comments.deleted'))
      reload()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('comments.title')}</h1>
          <p className="muted">{t('comments.subtitle')}</p>
        </div>
        <div className="row">
          <select
            value={source}
            onChange={(e) => setSource(e.target.value as SourceFilter)}
            style={{ width: 'auto' }}
            aria-label={t('comments.source')}
          >
            {SOURCE_FILTERS.map((s) => (
              <option key={s} value={s}>{t(`comments.source_${s}`)}</option>
            ))}
          </select>
          <select
            value={status}
            onChange={(e) => setStatus(e.target.value)}
            style={{ width: 'auto' }}
            aria-label={t('comments.status')}
          >
            {STATUSES.map((s) => (
              <option key={s} value={s}>{t(`comments.status_${s}`)}</option>
            ))}
          </select>
        </div>
      </PageHead>

      {!loading && items.length > 0 && (
        <div className="row" style={{ gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
          <span className="muted">{t('comments.count', { n: items.length })}</span>
          {source === 'all' && SOURCES.filter((s) => counts[s]).map((s) => (
            <span key={s} className={`badge ${SOURCE_API[s].tone}`}>
              {t(`comments.source_${s}`)} · {counts[s]}
            </span>
          ))}
        </div>
      )}

      {err && <div className="error-box">{err}</div>}
      {source !== 'all' && <HighlightBanner kind={t('comments.noun')} />}
      {loading && items.length === 0 && <p className="muted">{t('common.loading')}</p>}
      {!loading && items.length === 0 && !err && <p className="muted">{t('comments.empty')}</p>}

      {items.map((c) => {
        const highlighted = source !== 'all' && highlight.isHighlighted(c.id)
        return (
          <div
            className={`card${highlighted ? ' is-highlighted' : ''}`}
            key={`${c.source}:${c.id}`}
            data-highlight-id={source !== 'all' ? String(c.id) : undefined}
          >
            <div className="comment-card-head">
              <div className="comment-card-meta">
                <span className={`badge ${SOURCE_API[c.source].tone}`}>{t(`comments.source_${c.source}`)}</span>
                <Link to={`/detail/users/${c.user_id}`}>
                  <strong>{c.user_name || t('common.user_ref', { id: c.user_id })}</strong>
                </Link>
                <span className="muted">
                  · {t(`comments.on_${c.source}`)}{' '}
                  <Link to={`${SOURCE_API[c.source].detail}/${c.targetId}`}>
                    {fmtId(c.targetId)}{c.targetTitle ? ` — ${c.targetTitle}` : ''}
                  </Link>
                </span>
                {c.flagged && <span className="badge off">{t('comments.flagged')}</span>}
              </div>
              <span className="muted" style={{ whiteSpace: 'nowrap' }}>{formatDateTime(c.created_at)}</span>
            </div>
            <p className="comment-card-body">{c.body}</p>
            <div className="comment-card-actions">
              <span className="muted">{t('comments.status')}:</span>
              <select value={c.status} onChange={(e) => setStatusFor(c, e.target.value)} style={{ width: 'auto' }}>
                {EDITABLE.map((s) => (
                  <option key={s} value={s}>{t(`comments.status_${s}`)}</option>
                ))}
              </select>
              <button className="btn danger" onClick={() => remove(c)}>{t('common.delete')}</button>
            </div>
          </div>
        )
      })}
    </div>
  )
}
