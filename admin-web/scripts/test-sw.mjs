// test-sw.mjs — behavioural tests for public/sw.js.
//
// WHY THIS EXISTS
// check-pwa.mjs asserts on the worker's SOURCE — that the never-cache list
// names /api/, that the guard runs before any respondWith. Those are useful,
// but they are assertions about text. This file runs the worker for real:
// it loads sw.js into a stub ServiceWorkerGlobalScope with a stub Cache API
// and a stub fetch, dispatches actual FetchEvents at it, and then INSPECTS
// WHAT ENDED UP IN THE CACHE.
//
// That distinction matters because the promise this feature makes is a runtime
// one — "after an admin loads a screen full of donation records, none of those
// records are in cache storage" — and a runtime promise deserves a runtime
// test. The test below is the direct executable form of that sentence.
//
// Zero dependencies, like the other scripts here:   npm run test:sw
//
// Arrange → Act → Assert throughout; each case names the behaviour it pins.
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const swSource = readFileSync(join(here, '..', 'public/sw.js'), 'utf8')

const ORIGIN = 'https://admin.example.org'

// ─── Stub Cache API ──────────────────────────────────────────────────────
// A faithful-enough CacheStorage: enough surface for sw.js, and a plain Map
// underneath so a test can read exactly what was stored.

class StubCache {
  constructor() { this.store = new Map() }
  async put(req, res) { this.store.set(typeof req === 'string' ? req : req.url, res) }
  async match(req) { return this.store.get(typeof req === 'string' ? req : req.url) }
  async keys() { return [...this.store.keys()].map((url) => ({ url })) }
  async addAll(requests) {
    for (const r of requests) this.store.set(r.url, { ok: true, status: 200, type: 'basic' })
  }
}

class StubCacheStorage {
  constructor() { this.caches = new Map() }
  async open(name) {
    if (!this.caches.has(name)) this.caches.set(name, new StubCache())
    return this.caches.get(name)
  }
  async keys() { return [...this.caches.keys()] }
  async delete(name) { return this.caches.delete(name) }
  async match(req) {
    for (const c of this.caches.values()) {
      const hit = await c.match(req)
      if (hit) return hit
    }
    return undefined
  }
  /** Every URL currently stored, across every cache. */
  allUrls() {
    const urls = []
    for (const c of this.caches.values()) urls.push(...c.store.keys())
    return urls
  }
}

// ─── Stub request/response/event ─────────────────────────────────────────

/** Minimal Response with the header surface isCacheable() reads. */
function makeResponse(body, { status = 200, type = 'basic', headers = {} } = {}) {
  const h = new Map(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), v]))
  const res = {
    body, status, ok: status >= 200 && status < 300, type,
    headers: { get: (k) => h.get(k.toLowerCase()) ?? null },
  }
  // clone() must hand back an equivalent object — sw.js caches the clone and
  // returns the original, so a clone that shared state would hide a bug.
  res.clone = () => makeResponse(body, { status, type, headers })
  return res
}

function makeRequest(url, { method = 'GET', mode = 'no-cors' } = {}) {
  return { url: new URL(url, ORIGIN).href, method, mode }
}

/** A FetchEvent that records whether the worker claimed the request. */
function makeFetchEvent(request) {
  const event = { request, responded: false, response: undefined }
  event.respondWith = (p) => { event.responded = true; event.response = Promise.resolve(p) }
  return event
}

// ─── Load sw.js into a stub global scope ─────────────────────────────────

/**
 * Evaluate public/sw.js against fresh stubs and return the handles a test
 * needs. Re-run per test so no state leaks between cases.
 *
 * @param {(url: string) => object} fetchImpl what the "network" returns
 */
function loadWorker(fetchImpl) {
  const listeners = {}
  const cacheStorage = new StubCacheStorage()
  const fetchCalls = []

  const self = {
    addEventListener: (type, fn) => { (listeners[type] ||= []).push(fn) },
    location: { origin: ORIGIN },
    skipWaiting: async () => {},
    clients: { claim: async () => {} },
    registration: {},
  }

  const fetchStub = async (req) => {
    const url = typeof req === 'string' ? req : req.url
    fetchCalls.push(url)
    const res = fetchImpl(url)
    if (res instanceof Error) throw res
    return res
  }

  // `new Function` rather than a module import: sw.js is written against
  // globals (self, caches, fetch, Request) that only exist in a worker, and
  // this supplies exactly those. It also means the file under test is the
  // literal file that ships — not a re-export or a copy.
  const run = new Function('self', 'caches', 'fetch', 'Request', 'URL', 'console', swSource)
  run(self, cacheStorage, fetchStub, function Request(url, opts) { return makeRequest(url, opts) }, URL, console)

  const dispatch = async (type, event) => {
    const waits = []
    event.waitUntil = (p) => waits.push(p)
    for (const fn of listeners[type] || []) fn(event)
    await Promise.all(waits)
    if (event.response) await event.response.catch(() => {})
    return event
  }

  return { dispatch, cacheStorage, fetchCalls, listeners }
}

// ─── Test harness ────────────────────────────────────────────────────────
const results = []
async function test(name, fn) {
  try { await fn(); results.push({ name, ok: true }) }
  catch (err) { results.push({ name, ok: false, err: err.message }) }
}
function assert(cond, message) { if (!cond) throw new Error(message) }

// A response body standing in for the thing that must never be cached.
const DONATION_JSON = JSON.stringify({ items: [{ donor: 'Sizar Ahmed', amount: 250000, phone: '+9647510000000' }] })

// ─── The tests ───────────────────────────────────────────────────────────

await test('an authenticated API response is NOT in the cache after it is used', async () => {
  // Arrange — a worker whose network happily returns donation records.
  const w = loadWorker(() => makeResponse(DONATION_JSON))
  await w.dispatch('install', {})
  await w.dispatch('activate', {})

  // Act — the dashboard fetches a screenful of records, twice. Both URL shapes
  // the API actually serves are exercised: a plain path, and one ending in a
  // static-looking extension. The second is the one that matters — without the
  // never-cache guard the extension allow-list would happily store it, and a
  // test that only tried the first would pass while the leak was wide open.
  for (let i = 0; i < 2; i++) {
    await w.dispatch('fetch', makeFetchEvent(makeRequest('/api/admin/donations?page=1')))
    await w.dispatch('fetch', makeFetchEvent(makeRequest('/api/admin/donations/export.json')))
  }

  // Assert — the worker did not claim the request, and nothing about it was
  // stored. This is THE assertion this whole file exists for.
  const urls = w.cacheStorage.allUrls()
  assert(!urls.some((u) => u.includes('/api/')), `an /api/ URL reached cache storage: ${urls.join(', ')}`)
  const bodies = []
  for (const c of w.cacheStorage.caches.values()) for (const r of c.store.values()) bodies.push(String(r && r.body))
  assert(!bodies.some((b) => b.includes('Sizar Ahmed')), 'donor data was found inside a cached response body')
})

await test('the worker does not intercept an API request at all (no respondWith)', async () => {
  const w = loadWorker(() => makeResponse(DONATION_JSON))
  const e = await w.dispatch('fetch', makeFetchEvent(makeRequest('/api/admin/users')))
  // Not merely "uncached" — untouched. The browser performs the request as if
  // no worker existed, so nothing can go wrong in a caching branch later.
  assert(e.responded === false, 'the worker called respondWith() for an /api/ request')
})

await test('user-uploaded media (/images/) is never cached', async () => {
  const w = loadWorker(() => makeResponse('JPEGBYTES', { headers: { 'Content-Type': 'image/jpeg' } }))
  const e = await w.dispatch('fetch', makeFetchEvent(makeRequest('/images/id-cards/user-1001.jpg')))
  assert(e.responded === false, 'the worker intercepted a /images/ request')
  assert(w.cacheStorage.allUrls().every((u) => !u.includes('/images/')), '/images/ URL reached cache storage')
})

await test('an /api/ path is still bypassed when it ends in a static-looking extension', async () => {
  // Guards the ordering: the never-cache check must beat the extension
  // allow-list, or an export endpoint like /api/admin/export.json would be
  // treated as a static asset and stored.
  const w = loadWorker(() => makeResponse(DONATION_JSON))
  const e = await w.dispatch('fetch', makeFetchEvent(makeRequest('/api/admin/export/all.json')))
  assert(e.responded === false, 'an /api/ path with a .json suffix was treated as a static asset')
  assert(w.cacheStorage.allUrls().length === 0, 'something was cached for an /api/ .json path')
})

await test('a hashed static asset IS cached, and is served from cache next time', async () => {
  // The other half of the contract: the shell must actually work offline, so
  // the allow-list has to allow something.
  let networkHits = 0
  const w = loadWorker(() => { networkHits++; return makeResponse('console.log(1)') })
  await w.dispatch('activate', {})

  await w.dispatch('fetch', makeFetchEvent(makeRequest('/assets/index-a1b2c3.js')))
  assert(
    w.cacheStorage.allUrls().some((u) => u.includes('/assets/index-a1b2c3.js')),
    'a hashed asset was not cached — the app shell would not work offline',
  )

  const before = networkHits
  await w.dispatch('fetch', makeFetchEvent(makeRequest('/assets/index-a1b2c3.js')))
  assert(networkHits === before, 'a content-hashed asset was re-fetched instead of served from cache')
})

await test('a non-GET request is passed straight through', async () => {
  const w = loadWorker(() => makeResponse('{}'))
  const e = await w.dispatch('fetch', makeFetchEvent(makeRequest('/assets/x.js', { method: 'POST' })))
  assert(e.responded === false, 'a POST was intercepted')
})

await test('a cross-origin request is passed straight through', async () => {
  const w = loadWorker(() => makeResponse('font'))
  const e = await w.dispatch('fetch', makeFetchEvent({ url: 'https://fonts.gstatic.com/x.woff2', method: 'GET', mode: 'no-cors' }))
  assert(e.responded === false, 'a cross-origin request was intercepted')
  assert(w.cacheStorage.allUrls().length === 0, 'a cross-origin response was cached')
})

await test('a response marked private / no-store is refused even on an allowed path', async () => {
  // Defence in depth: if the server ever starts serving something per-user
  // from a static-looking URL, the storing side still says no.
  const w = loadWorker(() => makeResponse('secret', { headers: { 'Cache-Control': 'private, no-store' } }))
  await w.dispatch('fetch', makeFetchEvent(makeRequest('/assets/report-xyz.json')))
  assert(w.cacheStorage.allUrls().length === 0, 'a no-store response was cached')
})

await test('a response that varies by Authorization is refused', async () => {
  const w = loadWorker(() => makeResponse('per-user', { headers: { Vary: 'Authorization' } }))
  await w.dispatch('fetch', makeFetchEvent(makeRequest('/assets/whatever.json')))
  assert(w.cacheStorage.allUrls().length === 0, 'a credential-varying response was cached')
})

await test('an opaque (cross-origin) response is refused by the storing guard', async () => {
  const w = loadWorker(() => makeResponse('opaque', { type: 'opaque' }))
  await w.dispatch('fetch', makeFetchEvent(makeRequest('/assets/third-party.js')))
  assert(w.cacheStorage.allUrls().length === 0, 'an opaque response was cached')
})

await test('a navigation is served network-first and cached only as the shared shell', async () => {
  const w = loadWorker(() => makeResponse('<!doctype html><div id=root></div>'))
  await w.dispatch('fetch', makeFetchEvent(makeRequest('/users/1001', { mode: 'navigate' })))
  const urls = w.cacheStorage.allUrls()
  // Keyed by /index.html, never by the visited path — otherwise every route an
  // admin visits becomes its own independently-staling copy.
  assert(urls.some((u) => u.endsWith('/index.html')), 'the app shell was not cached under /index.html')
  assert(!urls.some((u) => u.includes('/users/1001')), 'the navigation was cached under the visited path')
})

await test('a navigation falls back to the cached shell when the network is down', async () => {
  let online = true
  const w = loadWorker(() => (online ? makeResponse('<!doctype html>SHELL') : new Error('offline')))
  await w.dispatch('fetch', makeFetchEvent(makeRequest('/', { mode: 'navigate' })))

  online = false
  const e = await w.dispatch('fetch', makeFetchEvent(makeRequest('/donations', { mode: 'navigate' })))
  const res = await e.response
  assert(res && String(res.body).includes('SHELL'), 'an offline navigation did not fall back to the cached shell')
})

await test('activate deletes caches from a previous worker version', async () => {
  const w = loadWorker(() => makeResponse('x'))
  const stale = await w.cacheStorage.open('balancenex-shell-v0')
  await stale.put('/assets/old.js', makeResponse('old'))
  await w.dispatch('activate', {})
  assert(!(await w.cacheStorage.keys()).includes('balancenex-shell-v0'), 'a stale cache survived activation')
})

// ─── Report ──────────────────────────────────────────────────────────────
const failed = results.filter((r) => !r.ok)
for (const r of results) console.log(`${r.ok ? '  ✓' : '  ✗'} ${r.name}${r.ok ? '' : `\n      ${r.err}`}`)
if (failed.length) {
  console.error(`\ntest-sw: ${failed.length} of ${results.length} failed.\n`)
  process.exit(1)
}
console.log(`\ntest-sw: ${results.length} passed.`)
