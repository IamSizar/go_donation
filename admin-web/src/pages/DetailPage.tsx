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
import { api, describeError, assetUrl, getStoredUser, isAdminLevel } from '../lib/api'
import { formatDateOnly, formatDateTime } from '../lib/dates'
import { useI18n, useFieldLabel, useStatusLabel } from '../lib/i18n'
import { skillLabelFor, scheduleSummary } from '../lib/skillCatalogue'
import { RESOURCE_LABELS } from '../lib/resourceLabels'
import PageHead from '../components/PageHead'
import { fmtId } from '../lib/formatId'
import { formatPhone } from '../lib/phone'
import UserProfileSections, { type UserDocument } from '../components/UserProfileSections'
import { USER_PROFILE_FIELD_BY_KEY } from '../lib/userProfileFields'

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

// Note #7, generalised — the "why is this empty" hint.
//
// It used to be three hard-coded key sets covering nine columns. The `users`
// resource now carries all 104 profile columns, and which role is asked for
// which of them is declared once in lib/userProfileFields.ts (read off
// `registration_field_rules`), so the users page routes through
// UserProfileSections and this helper is left for the ONE hint that is not
// role-derived.
function emptyFieldHint(key: string, t: (k: string) => string): string | null {
  if (key === 'email') return t('detail.field_email_hint')
  return null
}

// META_KEYS — the underscore-prefixed keys the backend adds to a users row that
// are NOT columns and must never be rendered as a field: the privacy flags and
// the uploaded-documents list. No database column starts with an underscore,
// which is why the prefix is a safe marker.
const META_KEYS = new Set(['_privacy_hidden', '_documents'])

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

/// Columns whose values are keys from the 28-entry skill catalogue.
///
/// `skill_tags` is the structured array; `skills` is the legacy free-text
/// column, which for anything submitted by the app holds the same key.
const SKILL_FIELD = /^(skill_tags|skills)$/

/// Columns holding the availability summary the APP produced, which it built
/// with English day names. The structured `availability_schedule` beside it
/// holds day keys, so that one localizes and this one cannot.
const AVAILABILITY_TEXT_FIELD = /^availability$/

function renderValue(
  key: string,
  val: unknown,
  t: (k: string) => string,
  statusLabel: (v: string) => string,
  locale?: string,
  row?: Record<string, unknown>,
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
    // Skill keys have their own 4-language catalogue — the same one the app
    // draws its chips from. statusLabel does not know them, so `first_aid`
    // reached an Arabic reader as `first_aid`.
    const parts = val.map((x) =>
      x !== null && typeof x === 'object'
        ? JSON.stringify(x)
        : SKILL_FIELD.test(key)
          ? skillLabelFor(String(x), locale)
          : statusLabel(String(x)),
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
  if (typeof val === 'string' && SKILL_FIELD.test(key)) {
    // The legacy free-text column holds catalogue keys for anything the app
    // submitted; a value that is not a key falls through unchanged, which is
    // right for a skill somebody typed themselves.
    return <span dir={dirFor(key)}>{skillLabelFor(val, locale)}</span>
  }
  if (typeof val === 'string' && AVAILABILITY_TEXT_FIELD.test(key)) {
    // "Mon 09:00-17:00, Tue …" — the English is IN THE DATA, written by the
    // form. It cannot be translated here, but the structured schedule stored
    // beside it can be, so prefer that and keep this as the fallback for rows
    // saved before that column existed.
    const localized = scheduleSummary(row?.availability_schedule, locale)
    if (localized) return <span dir={dirFor(key)}>{localized}</span>
  }
  // Localize controlled-vocabulary values (status/priority enums). statusLabel
  // returns the raw string when there's no matching status.* key, so free data
  // (names, cities) is left untouched.
  return <span dir={dirFor(key)}>{statusLabel(String(val))}</span>
}

export default function DetailPage() {
  const { resource = '', id = '' } = useParams<{ resource: string; id: string }>()
  const nav = useNavigate()
  const { t, locale } = useI18n()
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
      {resp && (() => {
        const isUser = resource === 'users'
        // One value renderer, shared with UserProfileSections, so the grouped
        // page and the generic one can never format the same column differently.
        const renderOne = (k: string, v: unknown) => {
          if (k === 'role_id') return <span>{roleLabel(v)}</span>
          if (USER_REF.test(k) || k === 'user_id') return <span>{userName(v)}</span>
          return renderValue(k, v, t, statusLabel, locale, resp.item as Record<string, unknown>)
        }
        // On the users page the profile columns are rendered by their own
        // grouped section below, so the flat list keeps only the ACCOUNT row —
        // who this login is, what state it is in, and its audit trail.
        const flatEntries = orderFields(
          Object.entries(resp.item).filter(
            ([k]) => !META_KEYS.has(k) && !(isUser && USER_PROFILE_FIELD_BY_KEY[k]),
          ),
        )
        const flat = (
          <div className="detail-grid">
            {flatEntries.map(([k, v]) => (
              <div key={k} className="detail-row">
                <div className="detail-key" title={k}>{fieldLabel(k)}</div>
                <div className="detail-value">{
                  v === null || v === undefined || v === ''
                    ? (() => {
                        const hint = isUser ? emptyFieldHint(k, t) : null
                        return hint
                          ? <span className="muted" title={hint}>— <em style={{ fontStyle: 'normal', fontSize: '0.9em' }}>({hint})</em></span>
                          : <span className="muted">—</span>
                      })()
                    : renderOne(k, v)
                }</div>
              </div>
            ))}
          </div>
        )
        if (!isUser) return flat
        const privacyHidden = Array.isArray(resp.item._privacy_hidden)
          ? (resp.item._privacy_hidden as unknown[]).map(String)
          : []
        const documents = Array.isArray(resp.item._documents)
          ? (resp.item._documents as UserDocument[])
          : []
        return (
          <div className="stack" style={{ gap: 24 }}>
            <section className="stack" style={{ gap: 12 }}>
              <h2 style={{ margin: 0, fontSize: '1.05rem' }}>{t('profile.group.account')}</h2>
              {flat}
            </section>
            <UserProfileSections
              item={resp.item}
              privacyHidden={privacyHidden}
              documents={documents}
              renderValue={renderOne}
              roleId={resp.item.role_id != null ? Number(resp.item.role_id) : undefined}
              // Owner #16 — the per-field required/optional/off control. The
              // client mirror of the ONE server gate on the field-rule setter
              // routes (main.go's `fieldRuleWrite`), so the screen offers only
              // what the server would accept. The server remains the
              // authority; this just avoids inviting a 403.
              canEditFieldRules={isAdminLevel(getStoredUser())}
            />
          </div>
        )
      })()}
    </div>
  )
}
