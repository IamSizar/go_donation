// CropDialog — the dashboard half of #20: choose a photo's shape before it is
// uploaded, matching what the app now offers on the phone.
//
// Deliberately dependency-free. A cropper library would be the obvious choice,
// but the whole job here is "drag a box over an <img>, then draw the selected
// rectangle to a canvas" — a few dozen lines against the DOM, versus a
// dependency that has to be kept current for the life of the dashboard.
//
// The crop box is stored in *natural image pixels*, not screen pixels, so the
// output is unaffected by how large the preview happens to render and a crop
// made on a laptop produces the same file as one made on a large monitor.

import { useCallback, useEffect, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { useI18n } from '../lib/i18n'

/** The same shapes the app offers, so a photo means one thing across both. */
export const SHAPES = [
  { key: 'free', label: 'crop.free', ratio: null },
  { key: 'square', label: 'crop.square', ratio: 1 },
  { key: 'standard', label: 'crop.standard', ratio: 4 / 3 },
  { key: 'wide', label: 'crop.wide', ratio: 16 / 9 },
] as const

export type ShapeKey = (typeof SHAPES)[number]['key']

type Box = { x: number; y: number; w: number; h: number }

type Props = {
  /** The file the admin just picked. */
  file: File | null
  /** Pins the crop to one shape and hides the chooser. */
  lockRatio?: ShapeKey
  /** Receives the cropped file, ready to upload. */
  onDone: (cropped: File) => void
  onCancel: () => void
}

/** Largest box of the given ratio that fits inside w×h, centred. */
function fitBox(w: number, h: number, ratio: number | null): Box {
  if (ratio === null) return { x: 0, y: 0, w, h }
  let bw = w
  let bh = w / ratio
  if (bh > h) {
    bh = h
    bw = h * ratio
  }
  return { x: (w - bw) / 2, y: (h - bh) / 2, w: bw, h: bh }
}

function clampBox(b: Box, w: number, h: number): Box {
  const bw = Math.min(b.w, w)
  const bh = Math.min(b.h, h)
  return {
    w: bw,
    h: bh,
    x: Math.max(0, Math.min(b.x, w - bw)),
    y: Math.max(0, Math.min(b.y, h - bh)),
  }
}

export default function CropDialog({ file, lockRatio, onDone, onCancel }: Props) {
  const { t } = useI18n()
  const [src, setSrc] = useState<string | null>(null)
  const [nat, setNat] = useState<{ w: number; h: number } | null>(null)
  const [shape, setShape] = useState<ShapeKey>(lockRatio ?? 'free')
  const [box, setBox] = useState<Box | null>(null)
  const [busy, setBusy] = useState(false)
  const imgRef = useRef<HTMLImageElement | null>(null)
  // Where the pointer went down, and the box as it was at that moment, both in
  // natural pixels. Held in a ref so a drag doesn't re-render on every move.
  const drag = useRef<{ px: number; py: number; from: Box; mode: 'move' | 'resize' } | null>(null)

  const ratio = SHAPES.find((s) => s.key === shape)?.ratio ?? null

  // Object URLs must be revoked or every pick leaks a blob for the life of
  // the tab.
  useEffect(() => {
    if (!file) {
      setSrc(null)
      return
    }
    const url = URL.createObjectURL(file)
    setSrc(url)
    setNat(null)
    setBox(null)
    setShape(lockRatio ?? 'free')
    return () => URL.revokeObjectURL(url)
  }, [file, lockRatio])

  // Re-fit whenever the shape changes, so switching to 1:1 always yields a
  // valid square rather than squashing whatever box was there.
  useEffect(() => {
    if (nat) setBox(fitBox(nat.w, nat.h, ratio))
  }, [nat, ratio])

  useEffect(() => {
    if (!file) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onCancel()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [file, onCancel])

  /** Screen px → natural image px. */
  const toNatural = useCallback((clientX: number, clientY: number) => {
    const img = imgRef.current
    if (!img || !nat) return null
    const r = img.getBoundingClientRect()
    return {
      x: ((clientX - r.left) / r.width) * nat.w,
      y: ((clientY - r.top) / r.height) * nat.h,
    }
  }, [nat])

  function onPointerDown(e: React.PointerEvent, mode: 'move' | 'resize') {
    if (!box) return
    e.preventDefault()
    e.stopPropagation()
    const p = toNatural(e.clientX, e.clientY)
    if (!p) return
    drag.current = { px: p.x, py: p.y, from: box, mode }
    ;(e.target as Element).setPointerCapture(e.pointerId)
  }

  function onPointerMove(e: React.PointerEvent) {
    const d = drag.current
    if (!d || !nat) return
    const p = toNatural(e.clientX, e.clientY)
    if (!p) return
    const dx = p.x - d.px
    const dy = p.y - d.py
    if (d.mode === 'move') {
      setBox(clampBox({ ...d.from, x: d.from.x + dx, y: d.from.y + dy }, nat.w, nat.h))
    } else {
      // Resize from the bottom-right corner; the top-left stays put.
      const minSide = 24
      const roomW = nat.w - d.from.x
      const roomH = nat.h - d.from.y
      if (ratio === null) {
        setBox({
          x: d.from.x,
          y: d.from.y,
          w: Math.min(Math.max(minSide, d.from.w + dx), roomW),
          h: Math.min(Math.max(minSide, d.from.h + dy), roomH),
        })
      } else {
        // The width leads and the height follows — but the width has to be
        // clamped against BOTH edges first, the bottom one expressed in width
        // terms. Deriving the height and then clamping the two independently
        // lets the box drift off-shape as soon as it meets an edge.
        const maxW = Math.min(roomW, roomH * ratio)
        const w = Math.min(Math.max(Math.min(minSide, maxW), d.from.w + dx), maxW)
        setBox({ x: d.from.x, y: d.from.y, w, h: w / ratio })
      }
    }
  }

  function onPointerUp() {
    drag.current = null
  }

  async function confirm() {
    const img = imgRef.current
    if (!img || !box || !file) return
    setBusy(true)
    try {
      const canvas = document.createElement('canvas')
      canvas.width = Math.max(1, Math.round(box.w))
      canvas.height = Math.max(1, Math.round(box.h))
      const ctx = canvas.getContext('2d')
      if (!ctx) throw new Error('canvas unavailable')
      ctx.drawImage(
        img,
        box.x, box.y, box.w, box.h,
        0, 0, canvas.width, canvas.height,
      )
      // PNG keeps transparency (logos); everything else goes out as JPEG so a
      // photo crop doesn't balloon to several megabytes.
      const png = file.type === 'image/png'
      const type = png ? 'image/png' : 'image/jpeg'
      const blob = await new Promise<Blob | null>((res) =>
        canvas.toBlob(res, type, png ? undefined : 0.9),
      )
      if (!blob) throw new Error('encode failed')
      const name = file.name.replace(/\.[^.]+$/, '') + (png ? '.png' : '.jpg')
      onDone(new File([blob], name, { type }))
    } finally {
      setBusy(false)
    }
  }

  // Fraction-of-the-image positioning, so the overlay tracks the <img> at any
  // size without a resize listener.
  const pct = (v: number, of: number) => `${(v / of) * 100}%`

  return (
    <AnimatePresence>
      {file && (
        <motion.div
          className="modal-overlay"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onCancel}
        >
          <motion.div
            className="modal-card crop-card"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 8 }}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="modal-head">
              <h2>{t('crop.title')}</h2>
              <button type="button" className="icon" onClick={onCancel} aria-label={t('common.cancel')}>
                ✕
              </button>
            </div>

            <div className="modal-body">
              {!lockRatio && (
                <div className="row crop-shapes">
                  {SHAPES.map((s) => (
                    <button
                      key={s.key}
                      type="button"
                      className={s.key === shape ? '' : 'secondary'}
                      onClick={() => setShape(s.key)}
                    >
                      {t(s.label)}
                    </button>
                  ))}
                </div>
              )}

              <div
                className="crop-stage"
                onPointerMove={onPointerMove}
                onPointerUp={onPointerUp}
                onPointerCancel={onPointerUp}
              >
                {src && (
                  <img
                    ref={imgRef}
                    src={src}
                    alt=""
                    draggable={false}
                    onLoad={(e) => {
                      const el = e.currentTarget
                      setNat({ w: el.naturalWidth, h: el.naturalHeight })
                    }}
                  />
                )}
                {box && nat && (
                  <div
                    className="crop-box"
                    style={{
                      left: pct(box.x, nat.w),
                      top: pct(box.y, nat.h),
                      width: pct(box.w, nat.w),
                      height: pct(box.h, nat.h),
                    }}
                    onPointerDown={(e) => onPointerDown(e, 'move')}
                  >
                    <span
                      className="crop-handle"
                      onPointerDown={(e) => onPointerDown(e, 'resize')}
                    />
                  </div>
                )}
              </div>

              {box && (
                <p className="muted crop-size">
                  {Math.round(box.w)} × {Math.round(box.h)} px
                </p>
              )}
            </div>

            <div className="modal-foot">
              <button type="button" className="secondary" onClick={onCancel} disabled={busy}>
                {t('common.cancel')}
              </button>
              <button type="button" className="primary" onClick={confirm} disabled={busy || !box}>
                {busy ? t('common.uploading') : t('crop.apply')}
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
