// FileInput — Phase 15 file picker used inside EditModal wherever a
// column holds a path to an image (logo_path, image_path, media_url,
// profile_picture, etc.).
//
// Behavior:
//   • Renders a preview if the current value looks like an image path.
//   • Lets the admin pick a file → uploads to POST /api/admin/upload.
//   • On success, calls onChange(newPath) with the server-returned path.
//   • Shows upload progress and any error inline.
//   • A small "Clear" button next to the preview blanks the field so the
//     admin can revert to no-image.
//
// Values exchanged with the parent are plain strings (the column type) so
// this component drops in anywhere a text input was used.

import { useRef, useState } from 'react'
import { api, describeError, assetUrl } from '../lib/api'
import { useI18n } from '../lib/i18n'

type Props = {
  value: string
  onChange: (next: string) => void
  disabled?: boolean
  // Optional accept hint; defaults to images only. Pass "image/*,.pdf" for
  // beneficiary case documents.
  accept?: string
  // When true, the preview thumbnail is hidden (e.g. for PDFs).
  hidePreview?: boolean
}

// Server response shape from POST /api/admin/upload.
type UploadResp = {
  success: true
  path: string
  size: number
  mime: string
}

function isImagePath(p: string): boolean {
  return /\.(png|jpe?g|gif|webp|svg)$/i.test(p)
}

export default function FileInput({
  value,
  onChange,
  disabled,
  accept = 'image/*',
  hidePreview,
}: Props) {
  const { t } = useI18n()
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement | null>(null)

  async function pickAndUpload(f: File) {
    setErr(null)
    setBusy(true)
    try {
      const form = new FormData()
      form.append('file', f)
      const res = await api.post<UploadResp>('/api/admin/upload', form, {
        headers: { 'Content-Type': 'multipart/form-data' },
      })
      onChange(res.data.path)
    } catch (e) {
      setErr(describeError(e))
    } finally {
      setBusy(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  const showPreview = !hidePreview && value && isImagePath(value)

  return (
    <div className="file-input">
      {showPreview && (
        <img
          src={assetUrl(value)}
          alt=""
          className="file-input-preview"
          onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = 'none' }}
        />
      )}
      <div className="file-input-controls">
        <input
          type="text"
          value={value}
          placeholder={t('file.placeholder')}
          disabled={busy || disabled}
          onChange={(e) => onChange(e.target.value)}
        />
        <input
          ref={fileRef}
          type="file"
          accept={accept}
          disabled={busy || disabled}
          style={{ display: 'none' }}
          onChange={(e) => {
            const f = e.target.files?.[0]
            if (f) pickAndUpload(f)
          }}
        />
        <button
          type="button"
          className="secondary"
          disabled={busy || disabled}
          onClick={() => fileRef.current?.click()}
        >
          {busy ? t('common.uploading') : value ? t('common.replace') : t('common.upload')}
        </button>
        {value && !busy && (
          <button
            type="button"
            className="secondary"
            disabled={disabled}
            onClick={() => onChange('')}
            title={t('file.clear')}
          >
            ✕
          </button>
        )}
      </div>
      {err && <div className="file-input-err">{err}</div>}
    </div>
  )
}
