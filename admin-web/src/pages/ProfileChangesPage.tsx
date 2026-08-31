import { useCallback, useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import Table, { type Column } from '../components/Table'
import PageHead from '../components/PageHead'
import ActionsMenu from '../components/ActionsMenu'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { fmtId } from '../lib/formatId'
import { formatDateTime } from '../lib/dates'

// #22 — users' own name / photo changes wait here until staff approve them.
// The live profile is untouched until approval, so rejecting simply drops the
// request and nothing ever displayed the unapproved value.
type ChangeRequest = {
  id: number
  user_id: number
  user_name: string
  user_phone: string
  field: string
  old_value: string
  new_value: string
  status: string
  created_at: string
  decided_at: string | null
  // Who decided it and why. Both were written from the start but never read
  // back, so a decision showed no reviewer and a rejection showed no reason.
  decided_by_name?: string
  decide_note?: string
}

export default function ProfileChangesPage() {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const toast = useToast()
  const [items, setItems] = useState<ChangeRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [status, setStatus] = useState('pending')
  const [busyId, setBusyId] = useState<number | null>(null)

  const load = useCallback(() => {
    setLoading(true)
    setErr(null)
    api
      .get<{ items: ChangeRequest[] }>('/api/admin/profile-changes', { params: { status } })
      .then((r) => setItems(r.data.items ?? []))
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }, [status])

  useEffect(load, [load])

  const decide = async (r: ChangeRequest, approve: boolean) => {
    setBusyId(r.id)
    try {
      await api.post(`/api/admin/profile-changes/${r.id}/decide`, { approve })
      toast.success(approve ? t('profileChanges.approved') : t('profileChanges.rejected'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyId(null)
    }
  }

  // Task 2 (owner ask: "tags for profile changes") — the tag is DERIVED from
  // r.field, never stored or hand-applied. A stored tag can drift out of sync
  // with the actual diff (e.g. a request re-categorized after the fact still
  // showing its old label); a value computed straight from the field name on
  // every render can never disagree with the data it labels.
  //
  // Each request already carries exactly one `field` (backend note above:
  // profilechanges.FieldFullName / FieldPicture, handlers/profile.go), so one
  // row needs exactly one tag — there is no multi-field row to pick "most
  // significant" from today. The categories below are intentionally broader
  // than the two fields currently in use (contact/identity cover phone,
  // national ID, and address too) so a future field lands in the right
  // bucket without a code change, per the owner's own field list.
  type ChangeTag = 'identity' | 'contact' | 'media' | 'other'
  const CONTACT_FIELDS = new Set(['phone', 'address', 'city'])
  const IDENTITY_FIELDS = new Set(['full_name', 'national_id', 'date_of_birth', 'gender'])
  const categorizeField = (field: string): ChangeTag => {
    if (field === 'profile_picture') return 'media'
    if (IDENTITY_FIELDS.has(field)) return 'identity'
    if (CONTACT_FIELDS.has(field)) return 'contact'
    return 'other'
  }
  // Reusing the existing .badge.tone-* palette (index.css) rather than
  // inventing new tokens — every one of these is already defined and
  // verified in both light and dark themes elsewhere in the app.
  const TAG_TONE: Record<ChangeTag, string> = {
    identity: 'tone-primary',
    contact: 'tone-info',
    media: 'tone-warning',
    other: '',
  }
  const tagLabel = (tag: ChangeTag) => t(`profileChanges.tag_${tag}`)

  // A photo change is a path, not text — show it as an image so the reviewer
  // is judging the actual picture rather than a filename.
  const renderValue = (field: string, value: string) => {
    if (!value) return <span className="muted">—</span>
    if (field === 'profile_picture') {
      return <img src={value} alt="" style={{ height: 44, borderRadius: 8 }} />
    }
    return <span>{value}</span>
  }

  const columns: Column<ChangeRequest>[] = [
    { key: 'id', header: t('col.id'), width: '70px', cell: (r) => <strong>{fmtId(r.id)}</strong> },
    {
      key: 'user',
      header: t('col.user'),
      cell: (r) => (
        <div className="cell-stack">
          <span>{r.user_name || fmtId(r.user_id)}</span>
          <span className="muted">{r.user_phone}</span>
        </div>
      ),
    },
    {
      key: 'field',
      header: t('col.field'),
      // Same unguarded template lookup the status column below had. The backend
      // submits exactly two fields today (profilechanges.FieldFullName and
      // FieldPicture, handlers/profile.go:297-338) and both are keyed, so this
      // is correct right now — but a third field would print the literal
      // "profileChanges.field_occupation", so it degrades to the field name the
      // way fieldLabel does everywhere else.
      cell: (r) => {
        const key = `profileChanges.field_${r.field}`
        const label = t(key)
        return label === key ? r.field : label
      },
    },
    {
      // Task 2 — the tag pairs a colour-coded badge WITH its text label
      // (tagLabel), so colour is never the only signal — see the class
      // comment above categorizeField for why it's derived, not stored.
      key: 'tag',
      header: t('profileChanges.tag'),
      cell: (r) => {
        const tag = categorizeField(r.field)
        const tone = TAG_TONE[tag]
        return <span className={`badge${tone ? ` ${tone}` : ''}`}>{tagLabel(tag)}</span>
      },
    },
    { key: 'old', header: t('profileChanges.old'), cell: (r) => renderValue(r.field, r.old_value) },
    { key: 'new', header: t('profileChanges.new'), cell: (r) => renderValue(r.field, r.new_value) },
    { key: 'created', header: t('col.created'), cell: (r) => <span className="muted">{formatDateTime(r.created_at)}</span> },
    {
      key: 'status',
      header: t('col.status'),
      // Was `t(\`status.${r.status}\`)`. Every value the column holds today
      // (pending / approved / rejected — internal/profilechanges) does have a
      // status.* key, so nothing is visibly wrong right now; the problem is the
      // failure mode. translate() returns THE KEY ITSELF when it finds no entry
      // (src/lib/i18n.tsx:92), so a fourth state added on the server would print
      // the string "status.withdrawn" in the cell — worse than the raw token,
      // because it does not even look like data. statusLabel is the same lookup
      // with the fallback every other list page relies on: unknown values come
      // back verbatim, and scripts/check-labels.mjs is what stops them from
      // staying unknown.
      cell: (r) => <span className="muted">{statusLabel(r.status)}</span>,
    },
    {
      key: 'review',
      header: t('profileChanges.reviewed_by'),
      // A rejection reason is only meaningful once a decision exists, so this
      // stays empty while the request is pending — that is the answer to
      // "clarify the cases in which rejection reasons are displayed": on any
      // decided request that carries a note, and only then.
      cell: (r) =>
        r.status === 'pending' ? (
          <span className="muted">—</span>
        ) : (
          <div className="cell-stack">
            <span>{r.decided_by_name?.trim() || t('profileChanges.reviewer_unknown')}</span>
            {r.decided_at && (
              <span className="muted">{formatDateTime(r.decided_at)}</span>
            )}
            {r.decide_note?.trim() && (
              <span className="muted">
                {t('profileChanges.reason')}: {r.decide_note}
              </span>
            )}
          </div>
        ),
    },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '150px',
      cell: (r) =>
        r.status !== 'pending' ? (
          <span className="muted">—</span>
        ) : (
          <ActionsMenu
            items={[
              {
                key: 'approve',
                label: t('profileChanges.approve'),
                disabled: busyId === r.id,
                onClick: () => decide(r, true),
              },
              {
                key: 'reject',
                label: t('profileChanges.reject'),
                danger: true,
                disabled: busyId === r.id,
                onClick: () => decide(r, false),
              },
            ]}
          />
        ),
    },
  ]

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('nav.profile_changes')}</h1>
          <p className="muted">{t('profileChanges.subtitle')}</p>
        </div>
        <div className="row">
          <select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 'auto' }}>
            <option value="pending">{t('status.pending')}</option>
            <option value="approved">{t('status.approved')}</option>
            <option value="rejected">{t('status.rejected')}</option>
            <option value="all">{t('filter.all_statuses')}</option>
          </select>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}
      {!loading && <Table rows={items} columns={columns} rowKey={(r) => r.id} />}
    </div>
  )
}
