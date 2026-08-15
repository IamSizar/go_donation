// ContentContactEditor — K13. The contact details of a content page.
//
// WHY THIS EXISTS
// "تواصل معنا" was one sentence. The client asked it for a logo, a phone
// number, WhatsApp, an email address, social media links and an address, and
// none of them existed as fields — so nothing on that screen could be tapped,
// dialled or opened. Migration 112 adds the columns; this is the editor.
//
// It edits STRUCTURE, not content: every field starts empty and the owner
// supplies the real number, address and links. Nothing here is pre-filled.
//
// Controlled component — the parent (ContentPage) owns the form, the single
// Save, and the validation state, so the whole page saves with one button and
// an invalid field can gate that button.
//
// Validation is inline and per field, from lib/contactFields.ts, which mirrors
// the server's ValidateContact. The operator is told at the box rather than by
// a failed save.
import { useI18n } from '../lib/i18n'
import FileInput from './FileInput'

/** The subset of the page form this editor owns. */
export type ContactValues = {
  logo_path: string
  contact_phone: string
  contact_whatsapp: string
  contact_email: string
  social_links: string
  address_en: string
  address_ar: string
  address_ckb: string
  address_kmr: string
}

const ADDRESS_LANGS: Array<{ key: keyof ContactValues; labelKey: string; rtl: boolean }> = [
  { key: 'address_en', labelKey: 'common.lang_en', rtl: false },
  { key: 'address_ar', labelKey: 'common.lang_ar', rtl: true },
  { key: 'address_ckb', labelKey: 'common.lang_sorani', rtl: true },
  { key: 'address_kmr', labelKey: 'common.lang_badini', rtl: true },
]

type Props = {
  values: ContactValues
  onChange: (key: keyof ContactValues, value: string) => void
  /** field → error code, from validateContactFields. */
  errors: Record<string, string>
  disabled: boolean
}

export default function ContentContactEditor({ values, onChange, errors, disabled }: Props) {
  const { t } = useI18n()

  // One place for "label, input, and the reason it is wrong", so no field can
  // be added later without its error message.
  const textField = (
    key: keyof ContactValues,
    labelKey: string,
    opts: { rtl?: boolean; type?: string; inputMode?: 'tel' | 'email' | 'text'; placeholderKey?: string } = {},
  ) => (
    <label className="field">
      <span className="muted">{t(labelKey)}</span>
      <input
        type={opts.type ?? 'text'}
        inputMode={opts.inputMode}
        dir={opts.rtl ? 'rtl' : 'ltr'}
        disabled={disabled}
        placeholder={opts.placeholderKey ? t(opts.placeholderKey) : undefined}
        value={values[key]}
        onChange={(e) => onChange(key, e.target.value)}
        aria-invalid={errors[key] ? true : undefined}
      />
      {errors[key] && <span className="field-error">{t(`error.${errors[key]}`)}</span>}
    </label>
  )

  return (
    <div className="card stack" style={{ gap: 12 }}>
      <div>
        <h3 style={{ margin: 0 }}>{t('content.contact_title')}</h3>
        <p className="muted" style={{ marginTop: 4 }}>{t('content.contact_desc')}</p>
      </div>

      <label className="field">
        <span className="muted">{t('field.logo')}</span>
        <FileInput
          value={values.logo_path}
          onChange={(v) => onChange('logo_path', v)}
          disabled={disabled}
        />
        {errors.logo_path && <span className="field-error">{t(`error.${errors.logo_path}`)}</span>}
      </label>

      {/* inputMode="tel" brings up the number pad on a touch device; the field
          stays a text input because a public line legitimately carries "+",
          brackets and an extension. */}
      {textField('contact_phone', 'field.contact_phone', { inputMode: 'tel' })}
      {textField('contact_whatsapp', 'field.whatsapp', { inputMode: 'tel' })}
      {textField('contact_email', 'field.email', { type: 'email', inputMode: 'email' })}

      <label className="field">
        <span className="muted">{t('field.social_links')}</span>
        <textarea
          rows={3}
          disabled={disabled}
          placeholder={t('hint.one_link_per_line')}
          value={values.social_links}
          onChange={(e) => onChange('social_links', e.target.value)}
          aria-invalid={errors.social_links ? true : undefined}
        />
        {errors.social_links && <span className="field-error">{t(`error.${errors.social_links}`)}</span>}
      </label>

      {/* The address is prose a human reads, so it is localized like every
          other text on this page. */}
      {ADDRESS_LANGS.map(({ key, labelKey, rtl }) => (
        <label className="field" key={key}>
          <span className="muted">{`${t('field.address')} — ${t(labelKey)}`}</span>
          <textarea
            rows={2}
            dir={rtl ? 'rtl' : 'ltr'}
            disabled={disabled}
            value={values[key]}
            onChange={(e) => onChange(key, e.target.value)}
            aria-invalid={errors[key] ? true : undefined}
          />
          {errors[key] && <span className="field-error">{t(`error.${errors[key]}`)}</span>}
        </label>
      ))}
    </div>
  )
}
