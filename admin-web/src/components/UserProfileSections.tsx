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
// WHERE THE LATER PER-FIELD RULE CONTROL ATTACHES
// A follow-up adds a required/optional/off control per field. It belongs on
// <ProfileFieldRow>: that component already receives the ProfileField, so the
// control is one more cell in its row and needs no change to the grouping, the
// page, or the field declaration.

import { useState } from 'react'
import { assetUrl } from '../lib/api'
import { useI18n, useFieldLabel } from '../lib/i18n'
import PhotoViewer from './PhotoViewer'
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
}: {
  field: ProfileField
  value: unknown
  roleId: number | undefined
  privacyHidden: string[]
  renderValue: (key: string, value: unknown) => React.ReactNode
  onOpenPhoto: (src: string, label: string) => void
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

  const collected = isCollectedForRole(field.key, roleId)

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
      <div className="detail-value">{rendered}</div>
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
}: Props) {
  const { t } = useI18n()
  const [photo, setPhoto] = useState<{ src: string; label: string } | null>(null)

  return (
    <div className="stack" style={{ gap: 24 }}>
      {privacyHidden.length > 0 && (
        // Said once at the top so an operator understands what the badges mean
        // and does not read a private value as one the person published.
        <p className="muted" style={{ margin: 0 }}>
          {t('profile.privacy_note')}
        </p>
      )}

      {USER_PROFILE_GROUPS.map((group) => (
        <section key={group.titleKey} className="stack" style={{ gap: 12 }}>
          <h2 style={{ margin: 0, fontSize: '1.05rem' }}>{t(group.titleKey)}</h2>
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
              />
            ))}
          </div>
        </section>
      ))}

      <DocumentsSection documents={documents} onOpenPhoto={(src, label) => setPhoto({ src, label })} />

      {photo && <PhotoViewer src={photo.src} label={photo.label} onClose={() => setPhoto(null)} />}
    </div>
  )
}
