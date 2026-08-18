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
import { useEffect, useRef } from 'react'
import { useI18n } from '../lib/i18n'

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
