// generate-pwa-icons.mjs — regenerates admin-web/public/icons/* from the ET
// brand mark.
//
// WHY THIS EXISTS
// The PWA icon set is checked in (the browser fetches it at runtime; it is not
// something Vite can synthesize), but a checked-in binary with no recipe rots:
// the day the brand mark changes, nobody knows how the derived PNGs were made.
// This script IS the recipe. It is deliberately NOT part of `npm run build` —
// it is run by hand when public/et-logo.png changes:
//
//     node scripts/generate-pwa-icons.mjs
//
// REQUIREMENTS
// ImageMagick (`magick`). Deliberately not an npm dependency: this runs on a
// developer machine a handful of times in the project's life, and shipping an
// image-processing library in package.json to serve that would be a permanent
// liability for an occasional need (house rule 11 — every dependency is a
// liability).
//
// THE TWO ICON FAMILIES, AND WHY THEY DIFFER
//   • `any` (and the iOS apple-touch-icon) — the mark full-bleed. iOS applies
//     its own rounded-rect mask and Android's legacy path draws the icon as
//     given, so edge-to-edge brand blue is correct here.
//   • `maskable` — Android may crop this to a circle, a squircle, or a
//     teardrop, keeping only the central 80% "safe zone". A full-bleed mark
//     loses its corners to that crop, so these are re-composited: a brand-blue
//     canvas with the mark scaled down and centred, which keeps every stroke of
//     the "ET" well inside the safe zone under any mask shape.
import { execFileSync } from 'node:child_process'
import { mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const publicDir = join(here, '..', 'public')
const outDir = join(publicDir, 'icons')
const source = join(publicDir, 'et-logo.png')

// Brand blue, sampled from et-logo.png itself. Kept in sync with the
// <meta name="theme-color"> in index.html and `theme_color` in the manifest —
// all three are the same colour for the same reason: the icon, the browser
// chrome and the splash screen must not disagree.
const BRAND = '#1B37C9'

// Sizes chosen for what actually consumes them, not for completeness:
//   192/512 — the two sizes Android/Chrome installability requires.
//   180     — iOS apple-touch-icon (iOS ignores the manifest icon array).
//   152/167 — older iPad home-screen sizes iOS still asks for.
//   32      — desktop browser tab / bookmark bar.
const ANY_SIZES = [32, 152, 167, 180, 192, 512]
const MASKABLE_SIZES = [192, 512]

// Fraction of the maskable canvas the mark occupies. 0.60 sits comfortably
// inside the 80% safe zone with room for the mark's own visual weight.
const MASKABLE_SCALE = 0.6

mkdirSync(outDir, { recursive: true })

for (const size of ANY_SIZES) {
  const out = join(outDir, `icon-${size}.png`)
  execFileSync('magick', [source, '-resize', `${size}x${size}`, '-strip', out])
  console.log(`wrote icons/icon-${size}.png`)
}

for (const size of MASKABLE_SIZES) {
  const inner = Math.round(size * MASKABLE_SCALE)
  const out = join(outDir, `maskable-${size}.png`)
  execFileSync('magick', [
    '-size', `${size}x${size}`, `xc:${BRAND}`,
    '(', source, '-resize', `${inner}x${inner}`, ')',
    '-gravity', 'center', '-composite',
    '-strip', out,
  ])
  console.log(`wrote icons/maskable-${size}.png`)
}
