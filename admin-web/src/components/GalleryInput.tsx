// GalleryInput — #23. A repeatable list of image slots for a media post's
// gallery (media_posts.gallery text[]). Each row reuses FileInput (upload to
// /api/admin/upload or paste a path/URL). The value is exchanged as a JSON
// string array so it plugs straight into EditModal's string-keyed value map;
// EditModal parses it back to an array in buildPatch before sending.

import FileInput from './FileInput'
import { useI18n } from '../lib/i18n'

type Props = {
  value: string // JSON-encoded string[] (e.g. '["images/uploads/a.jpg"]')
  onChange: (nextJson: string) => void
  disabled?: boolean
}

function parse(value: string): string[] {
  if (!value) return []
  try {
    const arr = JSON.parse(value)
    return Array.isArray(arr) ? arr.map((x) => String(x)) : []
  } catch {
    return []
  }
}

export default function GalleryInput({ value, onChange, disabled }: Props) {
  const { t } = useI18n()
  const items = parse(value)

  const emit = (next: string[]) => onChange(JSON.stringify(next))

  const setAt = (i: number, next: string) => {
    const copy = [...items]
    copy[i] = next
    emit(copy)
  }
  const removeAt = (i: number) => emit(items.filter((_, idx) => idx !== i))
  const add = () => emit([...items, ''])

  return (
    <div className="gallery-input">
      {items.map((item, i) => (
        <div key={i} className="gallery-input-row" style={{ display: 'flex', gap: 8, alignItems: 'flex-start', marginBottom: 8 }}>
          <div style={{ flex: 1 }}>
            <FileInput value={item} onChange={(next) => setAt(i, next)} disabled={disabled} />
          </div>
          <button
            type="button"
            className="secondary"
            disabled={disabled}
            onClick={() => removeAt(i)}
            title={t('common.delete')}
          >
            ✕
          </button>
        </div>
      ))}
      <button type="button" className="secondary" disabled={disabled} onClick={add}>
        + {t('gallery.add_image')}
      </button>
    </div>
  )
}
