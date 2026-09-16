// mock-api.test.mjs — behavioural tests for scripts/mock-api.mjs.
//
// WHY THIS EXISTS
// The mock API is only worth running while it answers in the shapes the
// dashboard actually reads. A mock that has drifted from the backend makes a
// browser check pass against a server that does not exist, which is worse
// than no check at all. So this pins:
//   1. the shell's own requests (permissions/me, verify-password, the users
//      search, the polls) in the shapes lib/permissions.ts, PasswordGate.tsx,
//      UserPicker.tsx and AppShell read;
//   2. (the chat-group admin routes live in mock-api-chat-groups.test.mjs,
//      split out when this file passed 500 lines; npm run test:mock-api
//      runs both);
//   3. the three legacy chat lists and their messages;
//   4. the fallback for every other route, and the empty/error/slow scenarios;
//   5. two drift guards against sources of truth outside this folder: the
//      backend's permission module and action lists, and the localStorage keys
//      the app reads a session from;
//   6. that the server listens on 127.0.0.1 only, from the tests and from the
//      command line, because it serves a super_admin view with no credentials.
//
// Each test starts its own server on a port the OS picks (listen(0)), so the
// suite never collides with a running `npm run mock:api` or a local backend.
//
// Zero dependencies:   npm run test:mock-api
// Arrange → Act → Assert throughout; each case names the behaviour it pins.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { createMockServer, listenOnLoopback } from './mock-api.mjs'
import { startMock } from './mock-api-test-helpers.mjs'
import { PERMISSION_ACTIONS, PERMISSION_MODULES } from '../src/test/fixtures/permissions.ts'
import { SESSION_STORAGE_KEYS } from '../src/test/fixtures/session.ts'

const web = join(dirname(fileURLToPath(import.meta.url)), '..')

// ─── 1 · The shell's own requests ───────────────────────────────────────

test('permissions/me grants every action on every module, as a super_admin', async (t) => {
  const request = await startMock(t)

  const { status, body } = await request('GET', '/api/admin/permissions/me')

  assert.equal(status, 200)
  assert.equal(body.tier, 'super_admin')
  assert.deepEqual(Object.keys(body.permissions).sort(), [...PERMISSION_MODULES].sort())
  for (const [module, actions] of Object.entries(body.permissions)) {
    for (const action of PERMISSION_ACTIONS) {
      assert.equal(actions[action], true, `${module}.${action} should be allowed`)
    }
  }
})

test('verify-password answers ok:true, the field PasswordGate and the export PIN read', async (t) => {
  const request = await startMock(t)

  const { status, body } = await request('POST', '/api/admin/verify-password', { password: 'any' })

  assert.equal(status, 200)
  assert.deepEqual(body, { success: true, ok: true })
})

test('the users search filters by q and answers in the users-list envelope', async (t) => {
  const request = await startMock(t)

  const everyone = await request('GET', '/api/admin/users?per_page=8')
  const matched = await request('GET', '/api/admin/users?q=layla&per_page=8')

  assert.ok(everyone.body.data.length >= 3, 'a few users to pick from')
  assert.ok(matched.body.data.length >= 1, 'the search finds someone')
  assert.ok(matched.body.data.length < everyone.body.data.length, 'the search narrows the list')
  for (const user of matched.body.data) {
    assert.match(`${user.profile?.full_name} ${user.phone}`.toLowerCase(), /layla/)
  }
  assert.equal(matched.body.pagination.total_items, matched.body.data.length)
})

test('the shell polls answer in the shapes AppShell and its providers read', async (t) => {
  const request = await startMock(t)

  const counts = await request('GET', '/api/admin/pending-counts')
  const events = await request('GET', '/api/admin/events?limit=100')
  const unread = await request('GET', '/api/admin/notifications?page=1&per_page=1&read_status=unread')

  assert.equal(typeof counts.body.total, 'number')
  assert.ok(events.body.items.length > 0)
  assert.equal(typeof events.body.items[0].event_type, 'string')
  assert.equal(unread.body.items.length, 1)
  assert.equal(unread.body.items[0].is_read, 0)
  assert.ok(unread.body.total_items >= 1)
})

// ─── 3 · Legacy chats ────────────────────────────────────────────────────

test('the donor, marriage and staff chat routes list threads and their messages', async (t) => {
  const request = await startMock(t)
  const systems = [
    ['/api/admin/chats?kind=direct', (id) => `/api/admin/chats/${id}/messages`],
    ['/api/admin/marriage/chats', (id) => `/api/admin/marriage/chats/${id}/messages`],
    ['/api/admin/staff-chats?include_archived=1', (id) => `/api/admin/staff-chats/${id}/messages`],
  ]

  for (const [listPath, messagesPath] of systems) {
    const list = await request('GET', listPath)
    const messages = await request('GET', messagesPath(list.body.items[0].id))

    assert.ok(list.body.items.length > 0, `${listPath} lists threads`)
    assert.ok(messages.body.items.length > 0, `${listPath}'s first thread has messages`)
  }
})

test('each legacy chat has a multi-line message body with a comma, so an export can be checked by hand', async (t) => {
  // A conversation export must keep such a body in ONE cell (lib/chatExport.ts
  // → lib/csv.ts). Without one in the fixtures, a manual export against the
  // mock could not show whether it does.
  const request = await startMock(t)
  const systems = [
    ['/api/admin/chats?kind=direct', (id) => `/api/admin/chats/${id}/messages`],
    ['/api/admin/marriage/chats', (id) => `/api/admin/marriage/chats/${id}/messages`],
    ['/api/admin/staff-chats?include_archived=1', (id) => `/api/admin/staff-chats/${id}/messages`],
  ]

  for (const [listPath, messagesPath] of systems) {
    const list = await request('GET', listPath)
    const messages = await request('GET', messagesPath(list.body.items[0].id))

    const tricky = messages.body.items.filter((m) => m.body.includes('\n') && m.body.includes(','))
    assert.ok(tricky.length > 0, `${listPath}'s first thread has a multi-line body containing a comma`)
  }
})

test('the support view of donor chats lists different threads from the direct view', async (t) => {
  const request = await startMock(t)

  const direct = await request('GET', '/api/admin/chats?kind=direct')
  const support = await request('GET', '/api/admin/chats?kind=support')

  const directIds = new Set(direct.body.items.map((th) => th.id))
  assert.ok(support.body.items.length > 0)
  for (const thread of support.body.items) assert.equal(directIds.has(thread.id), false)
})

// ─── 4 · Fallback and scenarios ─────────────────────────────────────────

test('any other route answers the empty success envelope', async (t) => {
  const request = await startMock(t)

  const get = await request('GET', '/api/admin/some-page-added-later')
  const post = await request('POST', '/api/admin/some-page-added-later', { x: 1 })

  assert.deepEqual(get, { status: 200, body: { success: true, items: [], data: [] } })
  assert.deepEqual(post, { status: 200, body: { success: true, items: [], data: [] } })
})

test('?scenario=error answers 500 on every API route', async (t) => {
  const request = await startMock(t)

  const groups = await request('GET', '/api/admin/chat-groups?scenario=error')
  const perms = await request('GET', '/api/admin/permissions/me?scenario=error')

  assert.equal(groups.status, 500)
  assert.equal(groups.body.success, false)
  assert.equal(perms.status, 500)
})

test('the scenario option sets the default, and ?scenario=default overrides it', async (t) => {
  const request = await startMock(t, { scenario: 'error' })

  const defaulted = await request('GET', '/api/admin/chat-groups')
  const overridden = await request('GET', '/api/admin/chat-groups?scenario=default')

  assert.equal(defaulted.status, 500)
  assert.equal(overridden.status, 200)
})

test('?scenario=empty empties every list but keeps the permission matrix', async (t) => {
  const request = await startMock(t)

  const groups = await request('GET', '/api/admin/chat-groups?scenario=empty')
  const users = await request('GET', '/api/admin/users?q=layla&scenario=empty')
  const perms = await request('GET', '/api/admin/permissions/me?scenario=empty')

  assert.deepEqual(groups.body.items, [])
  assert.deepEqual(users.body.data, [])
  assert.equal(users.body.pagination.total_items, 0)
  assert.ok(Object.keys(perms.body.permissions).length > 0)
})

test('?scenario=slow still answers normally once the delay has passed', async (t) => {
  const request = await startMock(t)

  const { status, body } = await request('GET', '/api/admin/chat-groups?scenario=slow')

  assert.equal(status, 200)
  assert.ok(body.items.length > 0)
})

test('an unknown scenario is refused instead of silently ignored', async (t) => {
  const request = await startMock(t)

  const { status, body } = await request('GET', '/api/admin/chat-groups?scenario=eror')

  assert.equal(status, 400)
  assert.match(body.error, /eror/)
})

// ─── 5 · Drift guards ────────────────────────────────────────────────────

test('the fixture module and action lists match backend/internal/permissions/permissions.go', () => {
  const go = readFileSync(join(web, '..', 'backend/internal/permissions/permissions.go'), 'utf8')
  const moduleBlock = /var Modules = \[\]string\{([\s\S]*?)\}/.exec(go)
  const actionBlock = /var AllActions = \[\]string\{([^}]*)\}/.exec(go)
  assert.ok(moduleBlock && actionBlock, 'permissions.go still declares Modules and AllActions')
  const constants = Object.fromEntries([...go.matchAll(/(Action\w+)\s*=\s*"([a-z_]+)"/g)].map((m) => [m[1], m[2]]))

  const modules = [...moduleBlock[1].matchAll(/"([a-z_]+)"/g)].map((m) => m[1])
  const actions = actionBlock[1].split(',').map((name) => constants[name.trim()])

  assert.deepEqual([...PERMISSION_MODULES], modules)
  assert.deepEqual([...PERMISSION_ACTIONS], actions)
})

test('the storage keys the start-up hint prints are the ones the app reads', () => {
  const apiSource = readFileSync(join(web, 'src/lib/api.ts'), 'utf8')
  const i18nSource = readFileSync(join(web, 'src/lib/i18n.tsx'), 'utf8')

  assert.ok(apiSource.includes(`const TOKEN_KEY = '${SESSION_STORAGE_KEYS.token}'`))
  assert.ok(apiSource.includes(`const USER_KEY = '${SESSION_STORAGE_KEYS.user}'`))
  assert.ok(i18nSource.includes(`localStorage.getItem('${SESSION_STORAGE_KEYS.locale}')`))
})

// ─── 6 · Network exposure ────────────────────────────────────────────────
// Every route answers without credentials and the start-up banner prints a
// super_admin session, so the server must never be reachable from another
// machine. A listen() without a host binds every interface (`::`).

test('listenOnLoopback binds the server to 127.0.0.1 only, never to every interface', async (t) => {
  const server = createMockServer({ log: () => {} })
  t.after(
    () =>
      new Promise((resolve) => {
        server.closeAllConnections()
        server.close(resolve)
      }),
  )

  const address = await listenOnLoopback(server, 0)

  assert.equal(address.address, '127.0.0.1')
  assert.equal(server.address().address, '127.0.0.1')
})

test('the command-line entry point starts the server through listenOnLoopback', () => {
  // The CLI block only runs when mock-api.mjs is the entry point, on a fixed
  // port, so it cannot be started from inside this suite. Pinning that it goes
  // through the helper tested above keeps it from binding every interface.
  const source = readFileSync(join(web, 'scripts/mock-api.mjs'), 'utf8')
  const start = source.indexOf('if (isEntryPoint)')
  assert.notEqual(start, -1, 'mock-api.mjs still has its `if (isEntryPoint)` block')

  const cli = source.slice(start)

  assert.match(cli, /listenOnLoopback\(server, port\)/)
  assert.doesNotMatch(cli, /\.listen\(/, 'the CLI must not call server.listen itself')
})
