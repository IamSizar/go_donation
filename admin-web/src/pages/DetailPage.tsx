// DetailPage — Phase 16 read-only view of a single record.
//
// The page is generic: it takes a :resource and :id from the URL, hits
// /api/admin/detail/:resource/:id, and renders every field on the returned
// row as a definition list. No per-resource layout — keeps the page
// maintainable across schema changes.
//
// Use cases:
//   • Sharing a link to a specific case/partner/etc. with a colleague.
//   • Printing a record (it's a clean static layout).
//   • Read-only access without exposing the Edit modal.
//
// The page falls back to the resource list at /<resource> if the user
// clicks "Back" or if the lookup 404s.

import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, describeError, assetUrl } from '../lib/api'
import { useI18n, useFieldLabel, useStatusLabel } from '../lib/i18n'

type DetailResp = {
  success: true
  resource: string
  item: Record<string, unknown>
}

// Maps :resource path slug → human label + list URL. Anything not in this map
// renders as "Unknown resource" (the backend would 404 anyway).
const RESOURCE_LABELS: Record<string, { labelKey: string; list: string }> = {
  partners:                     { labelKey: 'noun.partner',               list: '/partners' },
  media:                        { labelKey: 'noun.media_post',            list: '/media' },
  community:                    { labelKey: 'noun.community_entry',       list: '/community' },
  marriage:                     { labelKey: 'noun.profile',               list: '/marriage' },
  products:                     { labelKey: 'noun.product',               list: '/marketplace' },
  orders:                       { labelKey: 'noun.order',                 list: '/marketplace' },
  beneficiary_cases:            { labelKey: 'noun.case',                  list: '/beneficiary' },
  beneficiary_project_requests: { labelKey: 'noun.project_request',       list: '/beneficiary' },
  sponsorships:                 { labelKey: 'noun.sponsorship',           list: '/sponsorships' },
  in_kind_donations:            { labelKey: 'noun.in_kind_donation',      list: '/in-kind' },
  support_tickets:              { labelKey: 'noun.support_ticket',        list: '/support' },
  donations:                    { labelKey: 'noun.donation',              list: '/donations' },
  volunteer_applications:       { labelKey: 'noun.volunteer_application', list: '/volunteers' },
  volunteer_missions:           { labelKey: 'noun.mission',               list: '/missions' },
  campaigns:                    { labelKey: 'noun.campaign',              list: '/campaigns' },
  users:                        { labelKey: 'noun.user',                  list: '/users' },
}

// Heuristic: any string-valued column whose key ends in _path or _url and
// whose value looks like an image gets rendered as a preview thumbnail.
function looksLikeImagePath(key: string, val: unknown): boolean {
  if (typeof val !== 'string' || val === '') return false
  if (!/(_path|_url)$/i.test(key)) return false
  return /\.(png|jpe?g|gif|webp|svg)$/i.test(val)
}

// Heuristic: keys ending in _ar/_sorani/_badini get rtl direction in the
// rendered value cell.
function dirFor(key: string): 'rtl' | 'ltr' {
  return /(_ar|_sorani|_badini)$/i.test(key) ? 'rtl' : 'ltr'
}

function renderValue(
  key: string,
  val: unknown,
  t: (k: string) => string,
  statusLabel: (v: string) => string,
) {
  if (val === null || val === undefined || val === '') {
    return <span className="muted">—</span>
  }
  if (looksLikeImagePath(key, val)) {
    return <img src={assetUrl(String(val))} alt="" className="file-input-preview" />
  }
  if (typeof val === 'object') {
    return <pre className="audit-meta-panel" style={{ margin: 0 }}>{JSON.stringify(val, null, 2)}</pre>
  }
  if (typeof val === 'boolean') {
    return <span>{val ? t('common.yes') : t('common.no')}</span>
  }
  // Localize controlled-vocabulary values (status/priority enums). statusLabel
  // returns the raw string when there's no matching status.* key, so free data
  // (names, cities, dates) is left untouched.
  return <span dir={dirFor(key)}>{statusLabel(String(val))}</span>
}

export default function DetailPage() {
  const { resource = '', id = '' } = useParams<{ resource: string; id: string }>()
  const nav = useNavigate()
  const { t } = useI18n()
  const fieldLabel = useFieldLabel()
  const statusLabel = useStatusLabel()
  const [resp, setResp] = useState<DetailResp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  // Resolve user-id references (owner, donor, reviewed_by, …) to real names so
  // the read-only view shows "Sizar Ahmed (#18)" instead of a bare "18".
  const [userMap, setUserMap] = useState<Record<number, string>>({})
  useEffect(() => {
    let cancelled = false
    api
      .get<{ data?: Array<{ user_id: number; phone?: string | null; profile?: { full_name?: string | null } | null }> }>(
        '/api/admin/users', { params: { per_page: 1000 } })
      .then((r) => {
        if (cancelled) return
        const m: Record<number, string> = {}
        for (const u of r.data?.data ?? []) {
          m[u.user_id] = (u.profile?.full_name?.trim() || u.phone || '') as string
        }
        setUserMap(m)
      })
      .catch(() => {})
    return () => { cancelled = true }
  }, [])

  // role_id → role name, and *_user_id/*_by → user name.
  const ROLE_KEY: Record<number, string> = {
    1: 'registrations.role_donor', 2: 'registrations.role_beneficiary', 3: 'registrations.role_volunteer',
  }
  const roleLabel = (v: unknown) => {
    const k = ROLE_KEY[Number(v)]
    return k ? t(k) : String(v)
  }
  const userName = (v: unknown) => {
    const idn = Number(v)
    const n = userMap[idn]
    return n ? `${n} (#${idn})` : t('common.user_ref', { id: idn })
  }
  const USER_REF = /(_user_id|_by)$/

  const meta = RESOURCE_LABELS[resource]

  useEffect(() => {
    if (!resource || !id) return
    let cancelled = false
    setLoading(true)
    setErr(null)
    api
      .get<DetailResp>(`/api/admin/detail/${resource}/${id}`)
      .then((res) => { if (!cancelled) setResp(res.data) })
      .catch((e) => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [resource, id])

  if (!meta) {
    return (
      <div className="stack">
        <h1>{t('common.unknown_resource')}</h1>
        <p className="muted">{t('detail.no_view', { resource })}</p>
      </div>
    )
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t(meta.labelKey)} #{id}</h1>
          <p className="muted">{t('common.read_only_view')}</p>
        </div>
        <div className="row">
          <button className="secondary" onClick={() => nav(meta.list)}>{t('common.back_to_list')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}
      {resp && (
        <div className="detail-grid">
          {Object.entries(resp.item).map(([k, v]) => (
            <div key={k} className="detail-row">
              <div className="detail-key" title={k}>{fieldLabel(k)}</div>
              <div className="detail-value">{
                v === null || v === undefined || v === ''
                  ? <span className="muted">—</span>
                  : k === 'role_id'
                    ? <span>{roleLabel(v)}</span>
                    : (USER_REF.test(k) || k === 'user_id')
                      ? <span>{userName(v)}</span>
                      : renderValue(k, v, t, statusLabel)
              }</div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
