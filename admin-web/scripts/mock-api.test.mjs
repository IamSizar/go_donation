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
//   2. the chat-group admin routes the Phase 6 screens call, including the
//      after_id/limit paging the export loop depends on;
//   3. the three legacy chat lists and their messages;
//   4. the fallback for every other route, and the empty/error/slow scenarios;
//   5. two drift guards against sources of truth outside this folder: the
//      backend's permission module and action lists, and the localStorage keys
//      the app reads a session from.
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
import { createMockServer } from './mock-api.mjs'
import { MASKED_GROUP_ID, TEAM_GROUP_ID } from '../src/test/fixtures/chatGroups.ts'
import { PERMISSION_ACTIONS, PERMISSION_MODULES } from '../src/test/fixtures/permissions.ts'
import { SESSION_STORAGE_KEYS } from '../src/test/fixtures/session.ts'

const web = join(dirname(fileURLToPath(import.meta.url)), '..')

// ─── Helpers ─────────────────────────────────────────────────────────────

/**
 * Starts a mock server on a free port for one test and returns a request
 * function bound to it. The server is closed when that test ends.
 */
async function startMock(t, options = {}) {
  const server = createMockServer({ log: () => {}, slowMs: 10, ...options })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  t.after(
    () =>
      new Promise((resolve) => {
        server.closeAllConnections()
        server.close(resolve)
      }),
  )
  const { port } = server.address()
  return async (method, path, body) => {
    const res = await fetch(`http://127.0.0.1:${port}${path}`, {
      method,
      headers: body === undefined ? {} : { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
    return { status: res.status, body: await res.json() }
  }
}

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

// ─── 2 · Chat groups ─────────────────────────────────────────────────────

test('the chat-group list has a masked and a team group, in the admin list shape', async (t) => {
  const request = await startMock(t)

  const { status, body } = await request('GET', '/api/admin/chat-groups')

  assert.equal(status, 200)
  assert.deepEqual(body.items.map((g) => g.kind).sort(), ['masked', 'team'])
  for (const group of body.items) {
    assert.deepEqual(Object.keys(group).sort(), ['id', 'kind', 'last_at', 'last_message', 'title', 'unread_count'])
  }
})

test('a masked group serves its roster, messages and contact blocks', async (t) => {
  const request = await startMock(t)
  const base = `/api/admin/chat-groups/${MASKED_GROUP_ID}`

  const detail = await request('GET', base)
  const messages = await request('GET', `${base}/messages`)
  const blocks = await request('GET', `${base}/contact-blocks`)

  assert.equal(detail.body.group.kind, 'masked')
  assert.ok(detail.body.group.members.length >= 2)
  for (const member of detail.body.group.members) {
    assert.equal(member.masked, true)
    assert.ok(member.masked_label, 'every masked member has a label')
  }
  assert.ok(detail.body.group.members.some((m) => m.removed_at), 'one member was removed')
  const ids = messages.body.items.map((m) => m.id)
  assert.ok(ids.length >= 3)
  assert.deepEqual(ids, [...ids].sort((a, b) => a - b), 'messages are oldest first')
  assert.ok(blocks.body.items.length >= 1)
  for (const block of blocks.body.items) assert.equal(block.group_id, MASKED_GROUP_ID)
})

test('a team group serves a titled roster without masked labels', async (t) => {
  const request = await startMock(t)

  const { body } = await request('GET', `/api/admin/chat-groups/${TEAM_GROUP_ID}`)

  assert.equal(body.group.kind, 'team')
  assert.ok(body.group.member_title)
  for (const member of body.group.members) assert.equal(member.masked, false)
})

test('group messages page by after_id and limit, the way the export loop asks', async (t) => {
  const request = await startMock(t)
  const path = `/api/admin/chat-groups/${MASKED_GROUP_ID}/messages`
  const all = (await request('GET', `${path}?limit=100`)).body.items

  const page = await request('GET', `${path}?after_id=${all[0].id}&limit=1`)

  assert.deepEqual(page.body.items, [all[1]])
})

test('a group that does not exist answers 404 in the backend error envelope', async (t) => {
  const request = await startMock(t)

  const { status, body } = await request('GET', '/api/admin/chat-groups/999999')

  assert.equal(status, 404)
  assert.equal(body.success, false)
  assert.equal(typeof body.error, 'string')
})

test('a staff message posted to a group is appended to its history', async (t) => {
  const request = await startMock(t)
  const path = `/api/admin/chat-groups/${TEAM_GROUP_ID}/messages`

  const posted = await request('POST', path, { body: 'Deliveries start at nine.' })
  const blank = await request('POST', path, { body: '   ' })
  const history = await request('GET', path)

  assert.equal(posted.status, 200)
  assert.equal(typeof posted.body.message_id, 'number')
  assert.equal(history.body.items.at(-1).body, 'Deliveries start at nine.')
  assert.equal(history.body.items.at(-1).id, posted.body.message_id)
  assert.equal(blank.status, 400)
})

test('connect requests cover every status and filter by ?status=', async (t) => {
  const request = await startMock(t)

  const all = await request('GET', '/api/admin/chat-groups/connect-requests')
  const pending = await request('GET', '/api/admin/chat-groups/connect-requests?status=pending')
  const one = await request('GET', `/api/admin/chat-groups/connect-requests/${all.body.items[0].id}`)

  assert.deepEqual([...new Set(all.body.items.map((r) => r.status))].sort(), ['approved', 'declined', 'pending'])
  for (const r of all.body.items) assert.equal(typeof r.context_label, 'string')
  assert.ok(pending.body.items.length >= 1)
  for (const r of pending.body.items) assert.equal(r.status, 'pending')
  assert.equal(one.body.request.id, all.body.items[0].id)
  assert.equal(one.body.context_label, all.body.items[0].context_label)
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
