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
import { Link, useNavigate, useParams } from 'react-router-dom'
import { api, describeError, assetUrl } from '../lib/api'
import { formatDateOnly, formatDateTime } from '../lib/dates'
import { useI18n, useFieldLabel, useStatusLabel } from '../lib/i18n'
import { RESOURCE_LABELS } from '../lib/resourceLabels'
import PageHead from '../components/PageHead'
import { fmtId } from '../lib/formatId'
import { formatPhone } from '../lib/phone'

type DetailResp = {
  success: true
  resource: string
  item: Record<string, unknown>
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

// B9 — a timestamp reached this page as Go's RFC 3339 marshalling, so
// "تاريخ الإنشاء" read `2026-06-14T11:13:32.50385Z`. The formatters already
// exist and are used on 10+ other pages; this page simply never imported
// them, and a date string fell through to statusLabel, which returns an
// unrecognised value verbatim.
//
// Matched on the VALUE rather than the key name: `created_at` is a reliable
// signal but `next_due_date`, `dob` and `event_date` are not one convention,
// while the two ISO shapes are unmistakable and free text cannot collide
// with them.
const ISO_DATETIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/

// Note #7 — several user_profiles fields are only ever COLLECTED for one
// specific role's registration form (mobile app: registration_form.dart) —
// e.g. a Grantor is never even asked for "skills" or "family size". An empty
// value there isn't missing/broken data, it's a field that doesn't apply to
// this account's role. Rather than showing a bare "—" that reads as "this is
// broken," show WHY it's empty. Only meaningful on the `users` resource,
// where `role_id` is present on the row (1=grantor, 2=beneficiary,
// 3=volunteer — see RegistrationsPage.tsx's roleKey for the same mapping).
const VOLUNTEER_ONLY_FIELDS = new Set(['availability', 'experience', 'skills'])
const BENEFICIARY_ONLY_FIELDS = new Set(['family_size', 'housing_status', 'monthly_income'])

function emptyFieldHint(key: string, roleId: number | undefined, t: (k: string) => string): string | null {
  if (VOLUNTEER_ONLY_FIELDS.has(key) && roleId !== 3) return t('detail.field_volunteer_only')
  if (BENEFICIARY_ONLY_FIELDS.has(key) && roleId !== 2) return t('detail.field_beneficiary_only')
  if (key === 'email') return t('detail.field_email_hint')
  return null
}

// G8 — the client's note was that this page's field order "follows the English
// layout" and needs re-ordering. It was worse than that: there was no layout at
// all in either language. The row is built server-side as a Go map
// (`pgx.RowToMap` in admin_detail.go) and serialised with encoding/json, which
// documents that it sorts map keys — so the page rendered its fields in
// ALPHABETICAL ORDER OF THE ENGLISH COLUMN NAME. That is why it reads as an
// English layout to an Arabic reader: account_status, active, address,
// availability, city … is an ordering that only exists in English and carries
// no meaning in any language.
//
// So the fix is one designed order, applied to every resource rather than to
// `users` alone — the page is shared by all sixteen (App.tsx routes them all
// here), and a per-resource list would rot the moment a column is added.
//
// Three tiers. HEAD is the spine every record has some of, in the order a
// person actually asks the questions: which record is this, whose is it, what
// is it called, what state is it in, how do I reach them, where are they, who
// are they. TAIL is the audit trail — who reviewed it, when, and the
// timestamps — which is reference material, not what you opened the page for.
// Everything else keeps the order it arrived in, between the two.
//
// A key that is not listed simply falls in the middle; nothing is ever hidden
// or dropped by this function.
const FIELD_ORDER_HEAD = [
  // which record
  'id', 'case_code', 'profile_code', 'activity_code', 'transaction_code', 'code',
  // whose
  'user_id', 'username', 'owner_user_id', 'donor_user_id',
  // what it is called
  'full_name', 'name', 'name_ar', 'name_sorani', 'name_badini',
  'title', 'title_ar', 'title_sorani', 'title_badini',
  'public_title', 'public_title_ar', 'public_title_sorani', 'public_title_badini',
  'project_title', 'project_title_ar',
  // what state it is in
  'status', 'account_status', 'verification_status', 'registration_status',
  'active', 'is_active', 'public_visibility',
  'role_id', 'staff_tier', 'is_admin', 'is_guest',
  // how to reach them
  'phone', 'contact_phone', 'donor_phone', 'email', 'contact_email', 'website',
  // where
  'address', 'city', 'governorate', 'district', 'location',
  // who they are
  'gender', 'date_of_birth', 'national_id', 'marital_status', 'occupation',
]

const FIELD_ORDER_TAIL = [
  'review_notes', 'registration_reject_reason',
  'reviewed_by_user_id', 'registration_reviewed_by',
  'reviewed_at', 'registration_reviewed_at', 'registration_submitted_at',
  'created_at', 'updated_at',
]

// Stable: two keys in the same tier keep the order they arrived in, so an
// unlisted column never jumps around between page loads.
function orderFields(entries: [string, unknown][]): [string, unknown][] {
  const rank = (key: string): number => {
    const head = FIELD_ORDER_HEAD.indexOf(key)
    if (head !== -1) return head
    const tail = FIELD_ORDER_TAIL.indexOf(key)
    if (tail !== -1) return FIELD_ORDER_HEAD.length + 1 + tail
    return FIELD_ORDER_HEAD.length // the middle tier
  }
  return entries
    .map((entry, i) => ({ entry, i, r: rank(entry[0]) }))
    .sort((a, b) => (a.r - b.r) || (a.i - b.i))
    .map((x) => x.entry)
}

// E1 — a phone shown anywhere on the dashboard goes through the same helper,
// which groups the digits and pins the run left-to-right. Matched on the key
// name because the value is just a digit string: `phone`, `contact_phone`,
// `donor_phone`, `notify_phone`.
const PHONE_FIELD = /(^|_)phone$/

function renderValue(
  key: string,
  val: unknown,
  t: (k: string) => string,
  statusLabel: (v: string) => string,
) {
  if (typeof val === 'string' && val !== '' && PHONE_FIELD.test(key)) {
    return <span>{formatPhone(val)}</span>
  }
  if (val === null || val === undefined || val === '') {
    return <span className="muted">—</span>
  }
  if (looksLikeImagePath(key, val)) {
    return <img src={assetUrl(String(val))} alt="" className="file-input-preview" />
  }
  // B3 — a Postgres TEXT[] arrived as a JS array and fell into the object
  // branch below, so دليل المدينة → عرض printed `["commercial","government"]`
  // at an Arabic reader. Several resources carry one (city sectors, volunteer
  // skill_tags, marketplace labels, field_privacy), so this is the generic
  // fix rather than a per-column one.
  //
  // Each element goes through statusLabel — the same vocabulary the list
  // pages use for these values — and the separator is the Arabic comma, which
  // renders correctly in both directions.
  if (Array.isArray(val)) {
    if (val.length === 0) return <span className="muted">—</span>
    const parts = val.map((x) =>
      x !== null && typeof x === 'object' ? JSON.stringify(x) : statusLabel(String(x)),
    )
    return <span dir={dirFor(key)}>{parts.join('، ')}</span>
  }
  if (typeof val === 'object') {
    // Genuinely structured data (audit metadata) — a JSON panel is the honest
    // rendering, and it is not what the client reported.
    return <pre className="audit-meta-panel" style={{ margin: 0 }}>{JSON.stringify(val, null, 2)}</pre>
  }
  if (typeof val === 'boolean') {
    return <span>{val ? t('common.yes') : t('common.no')}</span>
  }
  if (typeof val === 'string') {
    if (ISO_DATETIME.test(val)) return <span>{formatDateTime(val)}</span>
    if (ISO_DATE.test(val)) return <span>{formatDateOnly(val)}</span>
  }
  // Localize controlled-vocabulary values (status/priority enums). statusLabel
  // returns the raw string when there's no matching status.* key, so free data
  // (names, cities) is left untouched.
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
      <PageHead>
        <div>
          {/* Note #11 — breadcrumb so the admin always knows where they are;
              the sidebar highlight alone used to vanish on this page.
              It shares one .page-head-meta line with the read-only note so
              BOTH lift into the strip above the Back button together — that
              leaves the <h1> alone in the block, so this page's title sits on
              the same centre line as every other section's. */}
          <div className="page-head-meta">
            <nav className="breadcrumb" aria-label={t('common.breadcrumb')}>
              <Link to={meta.list}>{t(meta.sectionKey)}</Link>
              <span aria-hidden="true"> &gt; </span>
              <span>{t(meta.labelKey)} {fmtId(id)}</span>
            </nav>
            <span className="muted">{t('common.read_only_view')}</span>
          </div>
          <h1>{t(meta.labelKey)} {fmtId(id)}</h1>
        </div>
        <div className="row">
          <button className="secondary" onClick={() => nav(meta.list)}>{t('common.back_to_list')}</button>
        </div>
      </PageHead>
      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}
      {resp && (
        <div className="detail-grid">
          {orderFields(Object.entries(resp.item)).map(([k, v]) => (
            <div key={k} className="detail-row">
              <div className="detail-key" title={k}>{fieldLabel(k)}</div>
              <div className="detail-value">{
                v === null || v === undefined || v === ''
                  ? (() => {
                      const hint = resource === 'users'
                        ? emptyFieldHint(k, Number(resp.item.role_id), t)
                        : null
                      return hint
                        ? <span className="muted" title={hint}>— <em style={{ fontStyle: 'normal', fontSize: '0.9em' }}>({hint})</em></span>
                        : <span className="muted">—</span>
                    })()
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
