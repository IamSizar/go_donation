// check-pwa.mjs — fails when the dashboard would stop being installable, or
// when the service worker would start caching data it must never cache.
//
// WHY THIS EXISTS
// Two failure modes, both silent, both only visible on a real phone weeks later:
//
//   1. INSTALLABILITY ROTS QUIETLY. Drop an icon, rename it, or let the
//      manifest link fall out of index.html, and Chrome simply stops offering
//      "Add to home screen". Nothing throws, nothing logs, `npm run build`
//      is green, and the owner just notices one day that the button is gone.
//
//   2. THE CACHE GROWS TEETH. public/sw.js is an ALLOW-LIST today: /api/ and
//      /images/ are bypassed, and only static extensions are stored. The
//      obvious "helpful" edit — cache the dashboard summary so it opens
//      instantly — puts one admin's donation records in an unauthenticated,
//      origin-scoped store that outlives their session and is shared with the
//      next person to sign in on that phone. That is the single most damaging
//      change anyone can make to this feature, so it is asserted against here
//      rather than left to review.
//
// Runs against BOTH the source (public/) and, when present, the build output
// (dist/) — dist is what actually ships, and a file that fails to be copied
// there is exactly the kind of gap the source alone cannot show.
//
// Zero dependencies, same as check-labels.mjs:   npm run check:pwa
import { existsSync, readFileSync, statSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const web = join(here, '..')
const read = (p) => readFileSync(p, 'utf8')

const failures = []
const checks = []
/** Assert, collecting rather than throwing so one run reports every problem. */
function check(ok, message) {
  checks.push(message)
  if (!ok) failures.push(message)
}

/**
 * Width and height of a PNG, read straight from the IHDR chunk.
 *
 * A hand-rolled 4-line parser instead of an image library because the only
 * question here is "does the file's real size match what the manifest claims",
 * and a manifest that promises 512x512 while shipping a 192px file is an icon
 * Android will reject — which is precisely the silent failure above.
 *
 * @param {string} path
 * @returns {{width: number, height: number}}
 */
function pngSize(path) {
  const buf = readFileSync(path)
  // Bytes 0-7 signature, 8-15 IHDR length+type, 16-19 width, 20-23 height.
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) }
}

// ─── 1. Manifest ─────────────────────────────────────────────────────────
const manifestPath = join(web, 'public/manifest.webmanifest')
check(existsSync(manifestPath), 'public/manifest.webmanifest exists')

if (existsSync(manifestPath)) {
  const m = JSON.parse(read(manifestPath))

  // The fields a browser needs before it will offer an install at all.
  for (const field of ['name', 'short_name', 'description', 'start_url', 'scope', 'display', 'theme_color', 'background_color']) {
    check(typeof m[field] === 'string' && m[field].length > 0, `manifest.${field} is set`)
  }
  check(m.display === 'standalone' || m.display === 'fullscreen', 'manifest.display is an installable mode')
  // House rule 3.5: portrait-locked unless a screen genuinely needs otherwise.
  check(m.orientation === 'portrait', 'manifest.orientation is portrait (house rule 3.5)')

  const icons = Array.isArray(m.icons) ? m.icons : []
  // Chrome's installability floor is a 192 and a 512; Android's adaptive icon
  // needs the maskable pair on top of that or it crops the mark's corners off.
  const has = (size, purpose) => icons.some((i) => i.sizes === `${size}x${size}` && i.purpose === purpose)
  check(has(192, 'any'), 'manifest declares a 192x192 "any" icon')
  check(has(512, 'any'), 'manifest declares a 512x512 "any" icon')
  check(has(192, 'maskable'), 'manifest declares a 192x192 "maskable" icon')
  check(has(512, 'maskable'), 'manifest declares a 512x512 "maskable" icon')

  // Every declared icon must exist AND actually be the size it claims.
  for (const icon of icons) {
    const file = join(web, 'public', icon.src.replace(/^\//, ''))
    if (!existsSync(file)) {
      check(false, `icon ${icon.src} exists on disk`)
      continue
    }
    const { width, height } = pngSize(file)
    check(
      `${width}x${height}` === icon.sizes,
      `icon ${icon.src} is really ${icon.sizes} (found ${width}x${height})`,
    )
    // A placeholder square compresses to almost nothing; the real mark does
    // not. Cheap guard against "ship a grey box to unblock the build".
    check(statSync(file).size > 200, `icon ${icon.src} is not an empty placeholder`)
  }
}

// ─── 2. index.html wiring ────────────────────────────────────────────────
const html = read(join(web, 'index.html'))
check(/<link[^>]+rel="manifest"[^>]+href="\/manifest\.webmanifest"/.test(html), 'index.html links the manifest')
check(/<link[^>]+rel="apple-touch-icon"/.test(html), 'index.html declares an apple-touch-icon (iOS ignores the manifest icons)')
check(/name="theme-color"/.test(html), 'index.html declares a theme-color')
check(/viewport-fit=cover/.test(html), 'index.html opts into the safe-area viewport')

// ─── 3. The service worker's caching rules ───────────────────────────────
// THE IMPORTANT SECTION. These are asserted on the source text because the
// behaviour they protect cannot be observed from a build artifact: a worker
// that caches /api/ looks identical to one that does not until an admin's
// records leak into the next session.
const swPath = join(web, 'public/sw.js')
check(existsSync(swPath), 'public/sw.js exists')

if (existsSync(swPath)) {
  const sw = read(swPath)
  // Strip comments so the prose explaining the rules cannot satisfy them.
  //
  // LINE comments must go FIRST. sw.js's own comments contain glob paths like
  // `/assets/*`, whose `/*` opens a block comment as far as a regex is
  // concerned — stripping blocks first swallowed everything from there to the
  // next `*/`, taking the real declarations with it and failing checks that
  // were actually fine. Removing whole `//` lines first leaves no such opener
  // behind. (Safe here because sw.js contains no `//` inside a string literal;
  // if one is ever added, this needs a real tokenizer, not a bigger regex.)
  const code = sw.replace(/\/\/[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '')

  check(/addEventListener\(\s*['"]fetch['"]/.test(code), 'sw.js has a fetch handler (required for installability)')

  // The data guard, asserted three ways: the prefixes are listed, they are
  // consulted, and the consultation happens BEFORE anything responds.
  check(/['"]\/api\/['"]/.test(code), 'sw.js names /api/ as never-cacheable')
  check(/['"]\/images\/['"]/.test(code), 'sw.js names /images/ as never-cacheable (user-uploaded media)')
  const guard = code.indexOf('NEVER_CACHE_PREFIXES.some')
  const firstRespond = code.indexOf('respondWith')
  check(guard !== -1, 'sw.js consults the never-cache prefix list')
  check(
    guard !== -1 && firstRespond !== -1 && guard < firstRespond,
    'sw.js checks the never-cache prefixes BEFORE any respondWith — an API request must never reach a caching branch',
  )

  check(/request\.method\s*!==\s*['"]GET['"]/.test(code), 'sw.js passes non-GET requests straight through')
  check(/url\.origin\s*!==\s*self\.location\.origin/.test(code), 'sw.js passes cross-origin requests straight through')

  // Nothing in the worker may read or persist a credential.
  check(!/localStorage|sessionStorage|indexedDB/.test(code), 'sw.js never touches persistent client storage (no token could be written there)')
  check(!/[Aa]uthorization\s*:/.test(code), 'sw.js never sets an Authorization header')
  // `Authorization` may appear in the worker for exactly one reason: the
  // isCacheable() guard that REFUSES to store a response the server marked as
  // varying by credential. Any other line mentioning it is reading or
  // forwarding a token, which this worker must never do. Checked per line
  // (rather than as one whole-file regex) so a second, unrelated mention
  // cannot hide behind the legitimate one.
  const authLines = code.split('\n').filter((l) => /authorization/i.test(l))
  check(
    authLines.every((l) => /Vary/.test(l)),
    'sw.js mentions Authorization only in the Vary guard that refuses to cache a credential-varying response' +
      (authLines.length ? `\n      offending line(s): ${authLines.filter((l) => !/Vary/.test(l)).map((l) => l.trim()).join(' | ')}` : ''),
  )
}

// ─── 4. What actually shipped ────────────────────────────────────────────
// public/ is only a promise; dist/ is the delivery. Skipped when dist is
// absent so the check still runs on a clean checkout.
const dist = join(web, 'dist')
if (existsSync(dist)) {
  for (const f of ['manifest.webmanifest', 'sw.js', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/maskable-192.png', 'icons/maskable-512.png', 'icons/icon-180.png']) {
    check(existsSync(join(dist, f)), `dist/${f} was emitted by the build`)
  }
  check(
    /rel="manifest"/.test(read(join(dist, 'index.html'))),
    'dist/index.html still links the manifest after the build',
  )
} else {
  console.log('check-pwa: dist/ not present — skipping build-output checks (run `npm run build` first to include them).')
}

// ─── Report ──────────────────────────────────────────────────────────────
if (failures.length) {
  console.error(
    `\ncheck-pwa: ${failures.length} of ${checks.length} checks failed:\n` +
      failures.map((f) => `  ✗ ${f}`).join('\n') +
      '\n\nThe caching assertions in section 3 are security constraints, not\n' +
      'style: read the header comment in public/sw.js before relaxing one.\n',
  )
  process.exit(1)
}
console.log(`check-pwa: ${checks.length} checks passed — installable, and the worker caches no user data.`)
