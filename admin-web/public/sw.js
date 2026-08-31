/* ============================================================
   sw.js — BalanceNex Admin service worker
   ============================================================
   Served from /sw.js (it lives in public/, so Vite copies it to the root of
   dist verbatim — a service worker can only control paths at or below its own
   URL, so root is the only place it can live).

   WHAT THIS IS FOR
   Two things, and only two:
     1. Installability. A browser will not offer "Add to home screen" without a
        registered service worker that has a fetch handler.
     2. An honest offline story for the SHELL — the HTML document, the hashed
        JS/CSS bundles, the fonts and the icons. Opening the installed app on a
        dead connection should give you the dashboard chrome and a banner
        saying the data is unreachable, not a browser dinosaur.

   ────────────────────────────────────────────────────────────
   WHAT THIS DELIBERATELY DOES NOT CACHE — READ BEFORE EDITING
   ────────────────────────────────────────────────────────────
   This dashboard shows other people's personal data: names, phone numbers,
   ID photographs, donation amounts, case files. A cache is a plain,
   origin-scoped, unauthenticated key/value store that OUTLIVES the session and
   is shared by every profile on the device. Putting an authenticated API
   response in it means:
     • the next admin to sign in on this phone can be served the previous
       admin's records, because the cache does not know a logout happened; and
     • a record edited or deleted on the server keeps rendering as current,
       which on a donations or beneficiary screen is not a stale pixel, it is a
       wrong answer to a question about money or a person.

   So the fetch handler is written as an ALLOW-LIST, not a block-list: a
   request is cached only if it positively matches a known-static shape, and
   everything else falls through to the network untouched (no respondWith at
   all, so the browser handles it exactly as if this worker did not exist).
   Specifically NEVER cached, and never stored anywhere by this file:
     • /api/**            — every authenticated JSON response.
     • /images/**         — user-uploaded media (ID photos, receipts, avatars).
     • the auth token     — this worker never reads, forwards, copies or stores
                            a credential; it does not touch request headers,
                            localStorage or IndexedDB at all.
     • any cross-origin   — Firebase, Google Fonts, anything else. Opaque
                            responses cannot be inspected for cacheability, so
                            they are simply passed through.
     • any non-GET        — passed through before anything else runs.
     • any response that is not a clean same-origin 200, or that carries a
       `Cache-Control: no-store` / `Vary: Authorization` hint.

   The one navigation response that IS cached is index.html, which is the same
   empty SPA document for every user, signed in or out. It contains no data.
   ============================================================ */

// Bump on every change to this file OR to the PRECACHE list. The activate
// handler deletes every cache whose name is not this one, which is what makes
// a deploy able to evict a shell that would otherwise be pinned forever.
const CACHE = 'balancenex-shell-v1'

// The document the SPA boots from. Cached at install so a cold offline launch
// has something to render; refreshed network-first on every online navigation
// so a deploy is picked up on the first load, not the second.
const APP_SHELL = '/index.html'

// Precached at install so the very first offline launch is not missing its
// chrome. Kept to files whose URLs are stable (the hashed /assets/* bundles
// cannot be listed here — their names are generated at build time — so they
// are picked up at runtime by the cache-first branch below instead).
const PRECACHE = [APP_SHELL, '/manifest.webmanifest', '/et-logo.png', '/favicon.svg', '/icons/icon-192.png']

// Paths whose responses may contain user or donation data. Matched first, and
// answered by doing nothing at all.
const NEVER_CACHE_PREFIXES = ['/api/', '/images/']

// Extensions the cache-first / stale-while-revalidate branch will consider.
// An allow-list, so a route that happens to end in something unexpected is
// passed through rather than stored.
const STATIC_EXT_RE = /\.(?:js|mjs|css|woff2?|ttf|otf|png|jpg|jpeg|svg|webp|ico|json)$/i

// ─── Install ────────────────────────────────────────────────────────────
// skipWaiting so a fresh worker takes over immediately. The alternative
// (waiting for every tab to close) means an admin on a phone, who never closes
// tabs, can run a months-old shell.
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      // `reload` bypasses the HTTP cache so we precache what the server has
      // right now, not a stale copy the browser was already holding.
      .then((cache) => cache.addAll(PRECACHE.map((u) => new Request(u, { cache: 'reload' }))))
      .then(() => self.skipWaiting())
      // A failed precache (one file 404s after a partial deploy) must not leave
      // the worker uninstalled forever — installability matters more than a
      // complete offline shell, and the runtime branches will fill the gap.
      .catch(() => self.skipWaiting()),
  )
})

// ─── Activate ───────────────────────────────────────────────────────────
// Drop every cache from a previous version, then claim open clients so the
// new worker controls the page that registered it without a reload.
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

/**
 * Is this response safe to put in a shared, session-outliving cache?
 *
 * Guards the storing side rather than trusting the routing side alone: even a
 * URL that looks static gets refused if the server marked it private or
 * varying by credentials.
 *
 * @param {Response|undefined} res
 * @returns {boolean}
 */
function isCacheable(res) {
  if (!res || !res.ok || res.status !== 200) return false
  // `basic` == same-origin and fully readable. `opaque`/`cors` responses either
  // cannot be inspected or come from a third party; neither belongs here.
  if (res.type !== 'basic') return false
  const cc = res.headers.get('Cache-Control') || ''
  if (/no-store|private/i.test(cc)) return false
  // A server that varies on the credential is telling us this body belongs to
  // one signed-in user. Believe it.
  if (/authorization|cookie/i.test(res.headers.get('Vary') || '')) return false
  return true
}

/**
 * Network-first, cache-fallback — used for the SPA document only.
 *
 * Online: always take the fresh document (so a deploy lands immediately) and
 * refresh the cached copy. Offline: hand back the cached shell so React boots
 * and can show the offline banner itself.
 *
 * @param {Request} request
 * @returns {Promise<Response>}
 */
async function documentStrategy(request) {
  try {
    const fresh = await fetch(request)
    if (isCacheable(fresh)) {
      const cache = await caches.open(CACHE)
      // Store under the canonical shell key, never under the visited URL:
      // /users and /donations are the same document, and keying by path would
      // fill the cache with duplicates that all go stale independently.
      await cache.put(APP_SHELL, fresh.clone())
    }
    return fresh
  } catch {
    const cached = await caches.match(APP_SHELL)
    // No cached shell either (first ever visit, offline) — let the browser
    // render its own network error, which is the honest thing to show.
    if (cached) return cached
    throw new Error('offline and no cached app shell')
  }
}

/**
 * Cache-first with a background refresh — used for static assets.
 *
 * The hashed /assets/* bundles are immutable, so a hit is always correct and
 * never needs revalidating. The unhashed public files (icons, fonts, the
 * manifest) are refreshed in the background so an edit lands on the next load.
 *
 * @param {Request} request
 * @param {boolean} immutable true for content-hashed URLs
 * @returns {Promise<Response>}
 */
async function staticStrategy(request, immutable) {
  const cached = await caches.match(request)
  if (cached && immutable) return cached

  const network = fetch(request)
    .then(async (res) => {
      if (isCacheable(res)) {
        const cache = await caches.open(CACHE)
        await cache.put(request, res.clone())
      }
      return res
    })
    // Offline with nothing cached: rethrow so the caller's `cached ?? network`
    // resolves to the failure the browser would have shown anyway.
    .catch((err) => {
      if (cached) return cached
      throw err
    })

  return cached || network
}

// ─── Fetch ──────────────────────────────────────────────────────────────
// Structured as a series of early returns. Every `return` without a
// respondWith() means "not our business" — the browser performs the request
// normally and nothing is stored.
self.addEventListener('fetch', (event) => {
  const { request } = event

  // 1. Only GET is ever cacheable. POST/PATCH/DELETE are state changes.
  if (request.method !== 'GET') return

  const url = new URL(request.url)

  // 2. Same-origin only. Firebase, Google Fonts and every other third party
  //    are passed through: their responses are opaque, so we could neither
  //    verify nor safely reuse them.
  if (url.origin !== self.location.origin) return

  // 3. THE DATA GUARD. Authenticated API responses and user-uploaded media
  //    never touch cache storage. See the header comment for why this is the
  //    single most important line in the file.
  if (NEVER_CACHE_PREFIXES.some((p) => url.pathname.startsWith(p))) return

  // 4. The SPA document — network-first so data screens are never served from
  //    a stale shell while online.
  if (request.mode === 'navigate') {
    event.respondWith(documentStrategy(request))
    return
  }

  // 5. Static assets. `/assets/` is Vite's content-hashed output directory:
  //    those filenames change whenever their bytes do, so a cached copy can
  //    never be wrong.
  if (STATIC_EXT_RE.test(url.pathname)) {
    event.respondWith(staticStrategy(request, url.pathname.startsWith('/assets/')))
    return
  }

  // 6. Anything else — passed straight through, uncached.
})

// Lets the page ask a waiting worker to take over immediately (used by the
// "update available" path in src/lib/pwa.ts).
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting()
})
