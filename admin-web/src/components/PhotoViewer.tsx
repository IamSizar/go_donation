// A photo opened in place, with every ordinary way out.
//
// WHY THIS EXISTS
// Check-in evidence was an `<a target="_blank">` around the thumbnail, so
// looking at a volunteer's photo threw the operator into a bare browser tab
// containing nothing but an image. That is not a viewer — it is a dead end:
// there is no close control, the dashboard is gone, and in an embedded browser
// view (a webview, a kiosk, the in-app preview) there may be no visible tab
// chrome to escape with either. The operator's only move is browser Back, and
// they arrive back at the top of the board having lost their place.
//
// It also broke the one job this photo has. Verifying a completion request
// means looking at the picture and the row TOGETHER — who, where, when — and a
// separate tab shows the picture with none of that.
//
// EVERY DISMISSAL PATH, because people reach for different ones: the × button,
// Escape, and clicking the backdrop. Matching AskDialog, which established
// those three here.
//
// DOWNLOADING goes through the backend rather than straight at the photo's own
// URL. Objects live on the R2 public bucket domain, a different origin that
// sends no CORS header, and that rules out every client-side route: fetch() is
// refused, and the <a download> attribute is *ignored* cross-origin, so the
// browser would navigate and simply open the photo in a bare tab — the dead end
// described above, reintroduced by the button meant to be useful. The backend
// relays the bytes with Content-Disposition: attachment instead.
import { useEffect, useRef, useState } from 'react'
import { useI18n } from '../lib/i18n'
import { api } from '../lib/api'

export type PhotoViewerProps = {
  src: string
  /** Describes the photo for screen readers and titles the viewer. */
  label: string
  onClose: () => void
}

export default function PhotoViewer({ src, label, onClose }: PhotoViewerProps) {
  const { t } = useI18n()
  const closeRef = useRef<HTMLButtonElement | null>(null)
  const openerRef = useRef<Element | null>(null)
  const [downloading, setDownloading] = useState(false)
  const [failed, setFailed] = useState(false)

  // Pulls the bytes through the backend and hands them to the browser as a
  // save. The object URL is revoked straight away — the download has already
  // been handed off by then, and leaving it alive pins the whole file in memory
  // for as long as the tab lives.
  async function download() {
    if (downloading) return
    setDownloading(true)
    setFailed(false)
    try {
      const res = await api.get<Blob>('/api/admin/media/download', {
        params: { path: src },
        responseType: 'blob',
      })
      const objectUrl = URL.createObjectURL(res.data)
      const link = document.createElement('a')
      link.href = objectUrl
      link.download = src.split(/[?#]/)[0].split('/').pop() || 'photo.jpg'
      document.body.appendChild(link)
      link.click()
      link.remove()
      URL.revokeObjectURL(objectUrl)
    } catch {
      // Surfaced in the viewer rather than thrown away, so a failed download
      // does not look like a button that simply does nothing.
      setFailed(true)
    } finally {
      setDownloading(false)
    }
  }

  // Focus moves to the close button on open and returns to the thumbnail on
  // close, so a keyboard operator is never dropped at the top of the page —
  // the same contract AskDialog keeps.
  useEffect(() => {
    openerRef.current = document.activeElement
    const timer = window.setTimeout(() => closeRef.current?.focus(), 50)
    return () => {
      window.clearTimeout(timer)
      const opener = openerRef.current
      if (opener instanceof HTMLElement && document.contains(opener)) opener.focus()
    }
  }, [])

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        e.preventDefault()
        onClose()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [onClose])

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={label}
      onClick={onClose}
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 1000,
        background: 'rgba(0,0,0,0.82)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 24,
      }}
    >
      <button
        ref={closeRef}
        type="button"
        onClick={onClose}
        aria-label={t('common.close')}
        title={t('common.close')}
        style={{
          position: 'absolute',
          // Directional, so the control sits in the same visual corner in
          // Arabic as in English rather than jumping across the screen.
          insetInlineEnd: 16,
          insetBlockStart: 16,
          width: 44, // 44px is the minimum comfortable touch target
          height: 44,
          borderRadius: 22,
          border: 'none',
          cursor: 'pointer',
          fontSize: 22,
          lineHeight: 1,
          color: '#fff',
          background: 'rgba(255,255,255,0.18)',
        }}
      >
        ×
      </button>

      {/* Sits beside the close control, in the same visual corner in both
          directions. Stops propagation so the click never reaches the
          backdrop's dismiss handler. */}
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation()
          void download()
        }}
        disabled={downloading}
        aria-label={t('common.download')}
        title={t('common.download')}
        style={{
          position: 'absolute',
          insetInlineEnd: 68, // clear of the 44px close button plus a gap
          insetBlockStart: 16,
          height: 44,
          paddingInline: 16,
          borderRadius: 22,
          border: 'none',
          cursor: downloading ? 'progress' : 'pointer',
          fontSize: 14,
          color: '#fff',
          background: 'rgba(255,255,255,0.18)',
          opacity: downloading ? 0.6 : 1,
        }}
      >
        {downloading ? t('common.downloading') : t('common.download')}
      </button>

      {failed && (
        <div
          role="alert"
          onClick={(e) => e.stopPropagation()}
          style={{
            position: 'absolute',
            insetBlockStart: 72,
            insetInlineEnd: 16,
            maxWidth: 320,
            padding: '10px 14px',
            borderRadius: 8,
            background: 'rgba(255,255,255,0.94)',
            color: '#7a1c1c',
            fontSize: 13,
            lineHeight: 1.4,
          }}
        >
          {t('common.download_failed')}
        </div>
      )}

      <img
        src={src}
        alt={label}
        // Stops a click ON the photo from closing it: people click an image to
        // look closer, and having that dismiss it feels like a misfire. The
        // backdrop around it still closes.
        onClick={(e) => e.stopPropagation()}
        style={{
          maxWidth: '100%',
          maxHeight: '100%',
          objectFit: 'contain',
          borderRadius: 8,
        }}
      />
    </div>
  )
}
