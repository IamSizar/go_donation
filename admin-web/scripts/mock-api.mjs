// mock-api.mjs — a credential-free stand-in for the Go API, so the dashboard
// can be looked at in a real browser with no database, no backend and no login.
//
// WHY THIS EXISTS
// Checking a dashboard screen by eye used to need a running backend, a seeded
// Postgres and a staff account with a password and a second factor. An agent
// or a new developer has none of those. This server answers the requests the
// shell makes on every page, plus the chat routes, with realistic data from
// src/test/fixtures/*.ts: the same fixtures the component tests use.
//
// HOW TO RUN (details in admin-web/docs/mock-api.md)
//   npm run mock:api                                                  127.0.0.1:8787, or MOCK_API_PORT
//   API_TARGET=http://127.0.0.1:8787 npm run dev -- --host 127.0.0.1  the SPA proxies /api here
// On start-up it prints the localStorage lines that skip the login screen.
//
// WHO CAN REACH IT
// Only this machine. The server listens on 127.0.0.1 (listenOnLoopback below),
// never on every interface, because every route answers without credentials
// and the start-up banner prints a super_admin session. Vite's own config
// binds every interface (host: true), hence the `--host 127.0.0.1` above.
//
// SCENARIOS: `?scenario=<name>` on one request, or MOCK_SCENARIO for all.
//   default  the fixtures, with POSTs remembered in memory until restart
//   empty    every top-level list empty and every total 0; objects unchanged
//   error    every request answers 500 { success: false, error: 'Database error.' }
//   slow     the default answer, 2 seconds late
//   no_sensitive  reading a masked group answers 403 sensitive_data_required
// An unknown name answers 400, so a typo cannot quietly look like "default".
//
// Every route the fixtures do not cover answers { success: true, items: [],
// data: [] }, which is the empty shape both list envelopes in the app read.
//
// Zero dependencies: node:http only. The fixtures are TypeScript, loaded with
// --experimental-strip-types, the flag check:feed-bodies already uses.
import { realpathSync } from 'node:fs'
import { createServer } from 'node:http'
import { fileURLToPath } from 'node:url'
import { MOCK_STAFF_USER, MOCK_TOKEN, SESSION_STORAGE_KEYS } from '../src/test/fixtures/session.ts'
import { createState, ROUTES } from './mock-api-routes.mjs'

/** Every scenario name a request or MOCK_SCENARIO may use. */
export const SCENARIOS = ['default', 'empty', 'error', 'slow', 'no_sensitive']

/** The only address the mock listens on: the IPv4 loopback interface. */
export const LOOPBACK_HOST = '127.0.0.1'

const DEFAULT_PORT = 8787
const DEFAULT_SLOW_MS = 2000
const FALLBACK_BODY = { success: true, items: [], data: [] }

// ─── Server ──────────────────────────────────────────────────────────────

/**
 * Builds the mock API server without starting it. Start it with
 * {@link listenOnLoopback}, never with a bare listen().
 *
 * Each server owns its own copy of the fixtures, so what one server's POSTs
 * change is never visible to another (or to the next test).
 *
 * @param {object} [options]
 * @param {string} [options.scenario]  scenario for requests that name none;
 *   defaults to MOCK_SCENARIO, then 'default'.
 * @param {number} [options.slowMs]    delay of the slow scenario; 2000 ms.
 * @param {(line: string) => void} [options.log]  receives one line per
 *   request; console.log by default.
 * @returns {import('node:http').Server}
 * @throws {Error} when the scenario is not one of SCENARIOS.
 */
export function createMockServer(options = {}) {
  const {
    scenario = process.env.MOCK_SCENARIO || 'default',
    slowMs = DEFAULT_SLOW_MS,
    log = console.log,
  } = options
  if (!SCENARIOS.includes(scenario)) {
    throw new Error(`Unknown scenario "${scenario}"; use one of: ${SCENARIOS.join(', ')}.`)
  }
  const context = { state: createState(), defaultScenario: scenario, slowMs, log }

  return createServer((req, res) => {
    handleRequest(context, req, res).catch((err) => {
      // A crash in a route is a bug in this mock. It is logged with its stack
      // and answered with a message saying so, so it can never be mistaken
      // for the deliberate "error" scenario.
      log(`[mock-api] ${req.method} ${req.url} crashed: ${err?.stack ?? err}`)
      send(res, 500, { success: false, error: 'The mock API crashed; see its console.' })
    })
  })
}

/**
 * Starts `server` on the loopback interface only.
 *
 * WHY: `listen(port)` with no host binds every interface (`::`), which would
 * put a credential-free super_admin API on the local network. Both the command
 * line below and the tests start the server through this one function, so the
 * host cannot be forgotten in one place.
 *
 * @param {import('node:http').Server} server  from {@link createMockServer}.
 * @param {number} port  the port; 0 lets the OS pick a free one.
 * @returns {Promise<import('node:net').AddressInfo>} the bound address, once listening.
 * @throws rejects with the listen error, such as EADDRINUSE.
 */
export function listenOnLoopback(server, port) {
  return new Promise((resolve, reject) => {
    server.once('error', reject)
    server.listen(port, LOOPBACK_HOST, () => {
      server.off('error', reject)
      resolve(server.address())
    })
  })
}

/** Answers one request and logs it with its status and scenario. */
async function handleRequest(context, req, res) {
  const url = new URL(req.url ?? '/', 'http://mock-api.local')
  const scenario = url.searchParams.get('scenario') ?? context.defaultScenario
  const reply = await replyFor(context, { method: req.method ?? 'GET', url, req, scenario })
  send(res, reply.status, reply.body)
  context.log(`[mock-api] ${req.method} ${url.pathname}${url.search} -> ${reply.status} (${scenario})`)
}

/** Decides the reply: scenario first, then the route table, then the fallback. */
async function replyFor(context, { method, url, req, scenario }) {
  if (!SCENARIOS.includes(scenario)) {
    return fail(400, `Unknown scenario "${scenario}"; use one of: ${SCENARIOS.join(', ')}.`)
  }
  if (scenario === 'error') return fail(500, 'Database error.')
  if (scenario === 'slow') await new Promise((resolve) => setTimeout(resolve, context.slowMs))

  const parsed = await readJsonBody(req)
  if (!parsed.ok) return fail(400, 'Invalid JSON.')
  const reply = dispatch(context.state, { method, url, body: parsed.value, scenario })
  return scenario === 'empty' ? emptied(reply) : reply
}

/** Runs the first route whose method and path match; the fallback otherwise. */
function dispatch(state, { method, url, body, scenario }) {
  for (const route of ROUTES) {
    if (route.method !== method) continue
    const match = route.path.exec(url.pathname)
    if (!match) continue
    // Every path parameter in the table is a numeric id.
    const params = match.slice(1).map(Number)
    return route.handle({ state, query: url.searchParams, body, scenario }, params)
  }
  return { status: 200, body: FALLBACK_BODY }
}

// ─── Scenario and transport helpers ─────────────────────────────────────

/**
 * The empty scenario. Every top-level array in the body becomes [] and every
 * pagination total becomes 0. Objects are left alone on purpose: the
 * permission matrix, a group's roster and the pending counts are not lists.
 */
function emptied(reply) {
  const body = { ...reply.body }
  for (const [key, value] of Object.entries(body)) {
    if (Array.isArray(value)) body[key] = []
  }
  const zeroTotals = { total_items: 0, total_pages: 1, has_more: false }
  if ('total_items' in body) Object.assign(body, zeroTotals)
  if (body.pagination) body.pagination = { ...body.pagination, ...zeroTotals }
  return { status: reply.status, body }
}

/**
 * Reads a JSON request body. An empty body is fine (value undefined); a body
 * that is not JSON is reported, never guessed at.
 */
async function readJsonBody(req) {
  const chunks = []
  for await (const chunk of req) chunks.push(chunk)
  const text = Buffer.concat(chunks).toString('utf8').trim()
  if (!text) return { ok: true, value: undefined }
  try {
    return { ok: true, value: JSON.parse(text) }
  } catch {
    return { ok: false }
  }
}

/** A failure in the backend's error envelope. */
function fail(status, error) {
  return { status, body: { success: false, error } }
}

/** Writes a JSON reply unless one was already sent. */
function send(res, status, body) {
  if (res.headersSent) return
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' })
  res.end(JSON.stringify(body))
}

// ─── Command line ───────────────────────────────────────────────────────

/**
 * The port from MOCK_API_PORT, or 8787 when it is unset. A set but invalid
 * value stops start-up instead of silently falling back to the default.
 */
function portFromEnv() {
  const raw = process.env.MOCK_API_PORT
  if (raw === undefined || raw === '') return DEFAULT_PORT
  const port = Number(raw)
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`MOCK_API_PORT must be a whole number from 1 to 65535, got "${raw}".`)
  }
  return port
}

/** Prints where the server is and how to point the dashboard at it. */
function printStartupHint(port, scenario) {
  const base = `http://${LOOPBACK_HOST}:${port}`
  const user = JSON.stringify(MOCK_STAFF_USER)
  console.log(`[mock-api] listening on ${base}, this machine only (scenario: ${scenario})`)
  console.log(`[mock-api] run the dashboard against it:  API_TARGET=${base} npm run dev -- --host ${LOOPBACK_HOST}`)
  console.log(`[mock-api] skip the login: open http://${LOOPBACK_HOST}:5173, paste this in its console, then reload:`)
  console.log(
    `  localStorage.setItem('${SESSION_STORAGE_KEYS.token}', '${MOCK_TOKEN}'); ` +
      `localStorage.setItem('${SESSION_STORAGE_KEYS.user}', '${user}'); ` +
      `localStorage.setItem('${SESSION_STORAGE_KEYS.locale}', 'en')`,
  )
}

// Runs only when this file is the entry point (`node scripts/mock-api.mjs`),
// not when the tests import createMockServer. realpath on both sides so a
// symlinked checkout still recognises itself.
const isEntryPoint =
  process.argv[1] !== undefined &&
  realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))

if (isEntryPoint) {
  const port = portFromEnv()
  const scenario = process.env.MOCK_SCENARIO || 'default'
  const server = createMockServer({ scenario })
  listenOnLoopback(server, port)
    .then(() => printStartupHint(port, scenario))
    .catch((err) => {
      console.error(`[mock-api] cannot listen on ${LOOPBACK_HOST}:${port}: ${err.message}`)
      process.exit(1)
    })
}
