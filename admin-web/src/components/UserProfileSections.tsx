// UserProfileSections — the `users` detail page, grouped.
//
// WHY THIS COMPONENT EXISTS
// DetailPage renders any resource as one flat definition list, which is right
// for a partner (30 columns) and wrong for a person (122 after the account row
// and the registration profile are merged). The owner asked to see "every
// single thing that the user added"; a 122-row alphabetical wall technically
// shows it and communicates nothing. So the user resource gets a layout, and
// every other resource keeps the generic one.
//
// Three things this does that the flat list could not:
//
//  1. GROUPS the fields the way the registration form asks for them, from the
//     one declaration in lib/userProfileFields.ts.
//  2. Distinguishes BLANK from NOT COLLECTED. The old screen printed the same
//     "—" for both, which is exactly what convinced the owner the app was not
//     saving anything. A field this role is never asked for now says so.
//  3. Shows PHOTOS AND DOCUMENTS as things you can look at, not as file paths.
//
// THE PER-FIELD RULE CONTROL (owner #16) LANDED HERE, as the earlier note
// predicted: <ProfileFieldRow> already received the field, the role and the
// value, so the control is one more cell in its row and the grouping, the
// page and the field declaration are untouched. It is <FieldRuleCell>, and
// everything about why it is dangerous and how it is made safe is written
// there — the short version is that the rule is per ROLE while this screen
// shows one PERSON, so the control names the role in every label and confirms
// before it writes.

import { useMemo, useState } from 'react'
import { ChevronDown, ChevronLeft } from 'lucide-react'
import { assetUrl } from '../lib/api'
import { useI18n, useFieldLabel } from '../lib/i18n'
import FieldRuleCell from './FieldRuleCell'
import PhotoViewer from './PhotoViewer'
import { useUserFieldRules, type ColumnRule } from '../lib/fieldRuleColumns'
import {
  USER_PROFILE_GROUPS,
  isCollectedForRole,
  privacyKeyFor,
  type ProfileField,
} from '../lib/userProfileFields'

/** One uploaded document, as the backend's `_documents` meta key sends it. */
export type UserDocument = {
  id: number
  case_id: number
  case_code: string
  document_type: string
  file_path: string
  public_allowed: boolean
  created_at: string
}

type Props = {
  /** The merged account + profile row from GET /api/admin/detail/users/:id. */
  item: Record<string, unknown>
  /** `_privacy_hidden` — the field keys the user hid from other users. */
  privacyHidden: string[]
  /** `_documents` — files uploaded against this user's beneficiary case. */
  documents: UserDocument[]
  /** Renders one ordinary value; supplied by DetailPage so the two agree. */
  renderValue: (key: string, value: unknown) => React.ReactNode
  /** The account's role, used to answer "was this ever asked for?". */
  roleId: number | undefined
  /**
   * Whether to offer the per-field required/optional/off control (owner #16).
   * False hides it entirely — see FieldRuleCell for why the server, not this
   * flag, is the authority.
   */
  canEditFieldRules?: boolean
}

/** Empty for display purposes: null, undefined, or a blank/whitespace string. */
function isBlank(v: unknown): boolean {
  return v === null || v === undefined || (typeof v === 'string' && v.trim() === '')
}

/** A path that a browser can render as an image, as opposed to a PDF etc. */
function isViewableImage(path: string): boolean {
  return /\.(png|jpe?g|gif|webp|avif|svg)(\?|$)/i.test(path)
}

// ─── One field row ──────────────────────────────────────────────────────────

/**
 * A single label/value row.
 *
 * This is the seam for the future per-field rule control: it already knows the
 * field, the role and the value, so a control cell can be added here alone.
 */
function ProfileFieldRow({
  field,
  value,
  roleId,
  privacyHidden,
  renderValue,
  onOpenPhoto,
  rule,
  canEditFieldRules,
  onRuleChanged,
}: {
  field: ProfileField
  value: unknown
  roleId: number | undefined
  privacyHidden: string[]
  renderValue: (key: string, value: unknown) => React.ReactNode
  onOpenPhoto: (src: string, label: string) => void
  /** This column's live rule for this role, or undefined while they load. */
  rule: ColumnRule | undefined
  canEditFieldRules: boolean
  onRuleChanged: () => void
}) {
  const { t } = useI18n()
  const fieldLabel = useFieldLabel()
  const label = fieldLabel(field.key)

  // The user's own privacy choice about this field, if the app offers a switch
  // for it at all. Staff still see the value — their access is governed by the
  // separate `sensitive_data` permission — but a value the person asked other
  // users not to see must not look like one they chose to share.
  const privacyKey = privacyKeyFor(field.key)
  const isPrivate = privacyKey !== null && privacyHidden.includes(privacyKey)

  // Owner #15 — the live rules, not the static snapshot, decide whether this
  // role was ever asked for the column. `liveRules` is undefined while the
  // fetch is in flight or if it failed, and isCollectedForRole then falls back
  // to the snapshot rather than rendering an unknown.
  const collected = isCollectedForRole(
    field.key,
    roleId,
    rule ? { [field.key]: { governed: rule.governed, state: rule.state } } : undefined,
  )

  let rendered: React.ReactNode
  if (!collected) {
    // Not an empty value — a question this role is never asked. Said plainly,
    // because reading it as missing data is the whole bug this page had.
    rendered = <span className="muted">{t('profile.not_collected')}</span>
  } else if (isBlank(value)) {
    rendered = <span className="muted">{t('profile.blank')}</span>
  } else if (field.kind === 'photo') {
    const path = String(value)
    const src = assetUrl(path)
    rendered = isViewableImage(path) ? (
      <button
        type="button"
        className="icon"
        style={{ padding: 0, background: 'none', border: 'none', cursor: 'zoom-in' }}
        onClick={() => onOpenPhoto(src, label)}
        aria-label={t('profile.open_photo', { name: label })}
      >
        <img src={src} alt={label} className="file-input-preview" />
      </button>
    ) : (
      // Not an image the browser will draw (a PDF CV, for example). A link is
      // the honest control; the viewer would show an empty box.
      <a href={src} target="_blank" rel="noreferrer">
        {t('profile.open_file')}
      </a>
    )
  } else {
    rendered = renderValue(field.key, value)
  }

  return (
    <div className="detail-row">
      <div className="detail-key" title={field.key}>
        {label}
        {isPrivate && (
          <span
            className="muted"
            style={{ marginInlineStart: 8, fontSize: '0.85em' }}
            title={t('profile.private_hint')}
          >
            {t('profile.private_badge')}
          </span>
        )}
      </div>
      <div className="detail-value">
        {rendered}
        {rule && (
          // The rule control sits UNDER the value, not beside it: the value is
          // what the operator came to read, and a dropdown competing with it
          // for the same line is how a mis-click starts.
          <div style={{ marginTop: 6 }}>
            <FieldRuleCell
              rule={rule}
              roleId={roleId}
              fieldLabel={label}
              canEdit={canEditFieldRules}
              onChanged={onRuleChanged}
            />
          </div>
        )}
      </div>
    </div>
  )
}

// ─── Documents ──────────────────────────────────────────────────────────────

/**
 * The files uploaded against this user's beneficiary case
 * (`beneficiary_case_documents`). Its own section rather than a field, because
 * it is a list of arbitrary length rather than one column.
 *
 * All four states are covered: the parent shows the skeleton and the error, and
 * an account with no documents gets a designed empty line rather than nothing.
 */
function DocumentsSection({
  documents,
  onOpenPhoto,
}: {
  documents: UserDocument[]
  onOpenPhoto: (src: string, label: string) => void
}) {
  const { t } = useI18n()
  return (
    <section className="stack" style={{ gap: 12 }}>
      <h2 style={{ margin: 0, fontSize: '1.05rem' }}>{t('profile.group.uploaded_documents')}</h2>
      {documents.length === 0 ? (
        <p className="muted" style={{ margin: 0 }}>
          {t('profile.no_documents')}
        </p>
      ) : (
        <div className="detail-grid">
          {documents.map((doc) => {
            const src = assetUrl(doc.file_path)
            const label = doc.document_type || t('profile.document')
            return (
              <div key={doc.id} className="detail-row">
                <div className="detail-key" title={doc.file_path}>
                  {label}
                  {doc.case_code && (
                    <span className="muted" style={{ marginInlineStart: 8, fontSize: '0.85em' }}>
                      {doc.case_code}
                    </span>
                  )}
                </div>
                <div className="detail-value">
                  {isViewableImage(doc.file_path) ? (
                    <button
                      type="button"
                      className="icon"
                      style={{ padding: 0, background: 'none', border: 'none', cursor: 'zoom-in' }}
                      onClick={() => onOpenPhoto(src, label)}
                      aria-label={t('profile.open_photo', { name: label })}
                    >
                      <img src={src} alt={label} className="file-input-preview" />
                    </button>
                  ) : (
                    <a href={src} target="_blank" rel="noreferrer">
                      {t('profile.open_file')}
                    </a>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}
    </section>
  )
}

// ─── The page body ──────────────────────────────────────────────────────────

export default function UserProfileSections({
  item,
  privacyHidden,
  documents,
  renderValue,
  roleId,
  canEditFieldRules = false,
}: Props) {
  const { t } = useI18n()
  const [photo, setPhoto] = useState<{ src: string; label: string } | null>(null)
  // Owner #15/#16 — one fetch of `registration_field_rules` for the whole
  // page, resolved onto columns for THIS account's role. `error` is surfaced
  // rather than swallowed; the resolver degrades to "nothing governed", which
  // renders the page exactly as it did before this change.
  const fieldRules = useUserFieldRules()
  const columnRules = fieldRules.rulesFor(roleId)

  // Which sections are open. The FIRST one starts open so the page does not
  // greet the operator with thirteen closed boxes and nothing to read; every
  // other section is a deliberate click.
  const [openSections, setOpenSections] = useState<Record<string, boolean>>(
    () => ({ [USER_PROFILE_GROUPS[0].titleKey]: true }),
  )
  // Rule controls are opt-in — see the toggle below for why.
  const [rulesMode, setRulesMode] = useState(false)

  /**
   * "9 / 14" per section: how many of its fields this person actually filled
   * in. It is what makes a collapsed section honest — an operator can see
   * there is nothing in `الصحة` without opening it, which is the whole reason
   * collapsing is safe here.
   *
   * A field counts as filled when it holds something other than empty string,
   * null or undefined. `0` and `false` COUNT: "0 children" is an answer, and
   * treating it as blank would under-report a section that is complete.
   */
  const filledCounts = useMemo(() => {
    const out: Record<string, { filled: number; total: number }> = {}
    for (const group of USER_PROFILE_GROUPS) {
      let filled = 0
      for (const f of group.fields) {
        const v = item[f.key]
        if (v !== undefined && v !== null && String(v).trim() !== '') filled++
      }
      out[group.titleKey] = { filled, total: group.fields.length }
    }
    return out
  }, [item])

  return (
    <div className="stack" style={{ gap: 24 }}>
      {fieldRules.error && (
        // Not swallowed and not fatal: the page still shows every value, it
        // just cannot say which fields are required — so it says that, rather
        // than quietly showing a snapshot as if it were live.
        <p className="muted" style={{ margin: 0 }}>{t('fieldrule.rules_unavailable')}</p>
      )}

      {privacyHidden.length > 0 && (
        // Said once at the top so an operator understands what the badges mean
        // and does not read a private value as one the person published.
        <p className="muted" style={{ margin: 0 }}>
          {t('profile.privacy_note')}
        </p>
      )}

      {/* ─── Rules mode ────────────────────────────────────────────────────
          The rule control repeats on ~90 rows. Showing all ninety at once
          turned a profile into a configuration screen: an operator who opened
          this page to READ somebody's details had to look past ninety
          controls to do it. So they are off by default and revealed together.

          It is a toggle rather than a separate screen because the rule
          belongs to the field it sits on — the owner's whole point in asking
          for it here — and because turning it on leaves every value in place
          rather than navigating away from the person you were reading. */}
      {canEditFieldRules && !fieldRules.error && (
        <label className="checkbox-field">
          <input
            type="checkbox"
            checked={rulesMode}
            onChange={(e) => setRulesMode(e.target.checked)}
          />
          {t('profile.rules_mode')}
        </label>
      )}

      {USER_PROFILE_GROUPS.map((group) => {
        const open = openSections[group.titleKey] ?? false
        const stats = filledCounts[group.titleKey]
        return (
          <section key={group.titleKey} className="profile-section">
            {/* ─── Collapsed by default ────────────────────────────────────
                Thirteen sections and 121 rows made this page 10,000px — about
                fourteen screens — and every visit started at the top of all
                of it. Collapsed, the same page is one screen of headings, and
                the count on each says whether it is worth opening, so nothing
                is hidden behind a guess. */}
            <button
              type="button"
              className="profile-section-head"
              aria-expanded={open}
              onClick={() =>
                setOpenSections((prev) => ({ ...prev, [group.titleKey]: !open }))
              }
            >
              {open ? <ChevronDown size={16} /> : <ChevronLeft size={16} />}
              <span className="profile-section-title">{t(group.titleKey)}</span>
              {/* Filled-of-total, so an empty section reads as empty from the
                  outside instead of after opening it. */}
              <span className="profile-section-count">
                {stats.filled} / {stats.total}
              </span>
            </button>
            {open && (
              <div className="detail-grid">
                {group.fields.map((field) => (
                  <ProfileFieldRow
                    key={field.key}
                    field={field}
                    value={item[field.key]}
                    roleId={roleId}
                    privacyHidden={privacyHidden}
                    renderValue={renderValue}
                    onOpenPhoto={(src, label) => setPhoto({ src, label })}
                    rule={
                      !rulesMode || fieldRules.loading || fieldRules.error
                        ? undefined
                        : columnRules[field.key]
                    }
                    canEditFieldRules={canEditFieldRules}
                    onRuleChanged={fieldRules.reload}
                  />
                ))}
              </div>
            )}
          </section>
        )
      })}

      <DocumentsSection documents={documents} onOpenPhoto={(src, label) => setPhoto({ src, label })} />

      {photo && <PhotoViewer src={photo.src} label={photo.label} onClose={() => setPhoto(null)} />}
    </div>
  )
}
