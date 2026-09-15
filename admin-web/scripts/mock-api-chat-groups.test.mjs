// mock-api-chat-groups.test.mjs — behavioural tests for the chat-group routes
// of scripts/mock-api.mjs.
//
// WHY THIS IS ITS OWN FILE
// These cases used to be section 2 of mock-api.test.mjs, which passed the
// 500-line limit once the conversation-export tests (#110) joined it. The
// shell, legacy chats, scenarios, drift guards and network exposure stay
// there; everything about chat groups is here.
//
// WHAT IT PINS
// The chat-group admin routes the Phase 6 screens call, in the shapes the
// backend sends: the list; the roster detail, including #111's per-member
// full_name and the lifecycle fields beside `group`; messages and their
// after_id paging; contact blocks; create; members and reactivation (decision
// D3); connect requests; and the refusal codes of the final error contract.
//
// Zero dependencies:   npm run test:mock-api   (runs both test files)
// Arrange → Act → Assert throughout; each case names the behaviour it pins.
import assert from 'node:assert/strict'
import test from 'node:test'
import { startMock } from './mock-api-test-helpers.mjs'
import { GUEST_USER_ID, MASKED_GROUP_ID, TEAM_GROUP_ID } from '../src/test/fixtures/chatGroups.ts'
import { ADMIN_USERS } from '../src/test/fixtures/shell.ts'

// ─── Reads ───────────────────────────────────────────────────────────────

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

test("a group detail carries each member's full_name and the lifecycle fields beside `group` (#111)", async (t) => {
  const request = await startMock(t)
  const path = `/api/admin/chat-groups/${MASKED_GROUP_ID}`
  const nameOf = (userId) => ADMIN_USERS.find((u) => u.user_id === userId)?.profile?.full_name ?? null

  await request('POST', `${path}/lifecycle`, { action: 'pause', reason: 'Under review' })
  const { status, body } = await request('GET', path)

  assert.equal(status, 200)
  assert.deepEqual(
    { lifecycle: body.lifecycle, lifecycle_reason: body.lifecycle_reason, is_archived: body.is_archived },
    { lifecycle: 'paused', lifecycle_reason: 'Under review', is_archived: false },
  )
  for (const member of body.group.members) {
    assert.equal(typeof member.full_name, 'string', `member ${member.user_id} has a name in the fixtures`)
    assert.equal(member.full_name, nameOf(member.user_id))
  }
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

test('a group that does not exist answers 404 group_not_found, for its detail, messages and contact blocks', async (t) => {
  const request = await startMock(t)

  const replies = [
    await request('GET', '/api/admin/chat-groups/999999'),
    await request('GET', '/api/admin/chat-groups/999999/messages'),
    await request('GET', '/api/admin/chat-groups/999999/contact-blocks'),
  ]

  for (const { status, body } of replies) {
    assert.equal(status, 404)
    assert.deepEqual(body, { success: false, error: 'Group not found.', code: 'group_not_found' })
  }
})

test('?scenario=no_sensitive refuses a masked group with 403 sensitive_data_required, and still serves a team group', async (t) => {
  const request = await startMock(t)
  const masked = `/api/admin/chat-groups/${MASKED_GROUP_ID}`
  const q = '?scenario=no_sensitive'

  const replies = [
    await request('GET', `${masked}${q}`),
    await request('GET', `${masked}/messages${q}`),
    await request('GET', `${masked}/contact-blocks${q}`),
  ]
  const team = await request('GET', `/api/admin/chat-groups/${TEAM_GROUP_ID}${q}`)

  for (const { status, body } of replies) {
    assert.equal(status, 403)
    assert.equal(body.code, 'sensitive_data_required')
  }
  assert.equal(team.status, 200)
})

test('a member added to a group and then removed shows in the roster with removed_at', async (t) => {
  const request = await startMock(t)
  const path = `/api/admin/chat-groups/${TEAM_GROUP_ID}`

  const added = await request('POST', `${path}/members`, { user_id: 101, role_in_group: 'donor', label: '' })
  const removed = await request('DELETE', `${path}/members/101`)
  const again = await request('DELETE', `${path}/members/101`)
  const { body } = await request('GET', path)

  assert.equal(added.status, 200)
  assert.equal(removed.status, 200)
  assert.equal(again.status, 404)
  const row = body.group.members.find((m) => m.user_id === 101)
  assert.equal(typeof row.removed_at, 'string')
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

// ─── Writes ──────────────────────────────────────────────────────────────

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

test('creating a group answers its group_id, and the list then shows it first', async (t) => {
  const request = await startMock(t)
  const body = {
    kind: 'team',
    member_title: 'Night shift',
    members: [{ user_id: 105, role_in_group: 'volunteer', label: '' }],
  }

  const created = await request('POST', '/api/admin/chat-groups', body)
  const list = await request('GET', '/api/admin/chat-groups')

  assert.equal(created.status, 200)
  assert.equal(typeof created.body.group_id, 'number')
  assert.deepEqual(
    { id: list.body.items[0].id, kind: list.body.items[0].kind, title: list.body.items[0].title },
    { id: created.body.group_id, kind: 'team', title: 'Night shift' },
  )
})

// ─── Refusals ────────────────────────────────────────────────────────────

test('a guest account is found by the users search but refused as a group member', async (t) => {
  const request = await startMock(t)
  const member = (userId) => ({ user_id: userId, role_in_group: 'donor', label: '' })

  const search = await request('GET', '/api/admin/users?q=guest&per_page=8')
  const created = await request('POST', '/api/admin/chat-groups', {
    kind: 'team', member_title: 'Night shift', members: [member(105), member(GUEST_USER_ID)],
  })
  const added = await request('POST', `/api/admin/chat-groups/${TEAM_GROUP_ID}/members`, member(GUEST_USER_ID))
  const groups = await request('GET', '/api/admin/chat-groups')
  const team = await request('GET', `/api/admin/chat-groups/${TEAM_GROUP_ID}`)

  // The search finding this id is also the check that shell.ts's guest row
  // and chatGroups.ts's GUEST_USER_ID still agree.
  assert.deepEqual(search.body.data.map((u) => u.user_id), [GUEST_USER_ID])
  for (const refused of [created, added]) {
    assert.equal(refused.status, 400)
    assert.equal(refused.body.code, 'guest_member_not_allowed')
  }
  assert.equal(groups.body.items.length, 2, 'the refused create wrote no group')
  assert.equal(team.body.group.members.some((m) => m.user_id === GUEST_USER_ID), false)
})

test('creating a group refuses a repeated person and a repeated masked label with 409 codes', async (t) => {
  const request = await startMock(t)
  const member = (userId, label = '') => ({ user_id: userId, role_in_group: 'donor', label })

  const repeatedPerson = await request('POST', '/api/admin/chat-groups', {
    kind: 'team', member_title: 'Night shift', members: [member(105), member(105)],
  })
  const repeatedLabel = await request('POST', '/api/admin/chat-groups', {
    kind: 'masked', member_title: '', members: [member(101, 'Donor A'), member(103, ' donor a ')],
  })
  const groups = await request('GET', '/api/admin/chat-groups')

  assert.equal(repeatedPerson.status, 409)
  assert.equal(repeatedPerson.body.code, 'group_member_conflict')
  assert.equal(repeatedLabel.status, 409)
  assert.equal(repeatedLabel.body.code, 'group_label_conflict')
  assert.equal(groups.body.items.length, 2, 'neither refused create wrote a group')
})

test('adding an active member again answers 409 group_member_conflict', async (t) => {
  const request = await startMock(t)

  const { status, body } = await request('POST', `/api/admin/chat-groups/${MASKED_GROUP_ID}/members`, {
    user_id: 101, role_in_group: 'donor', label: '',
  })

  assert.equal(status, 409)
  assert.equal(body.code, 'group_member_conflict')
})

test('re-adding a removed member reactivates them with their old label and role', async (t) => {
  const request = await startMock(t)
  const path = `/api/admin/chat-groups/${MASKED_GROUP_ID}`
  const before = (await request('GET', path)).body.group.members.find((m) => m.removed_at)

  const added = await request('POST', `${path}/members`, { user_id: before.user_id, role_in_group: 'volunteer', label: 'New name' })
  const after = (await request('GET', path)).body.group.members.filter((m) => m.user_id === before.user_id)

  assert.equal(added.status, 200)
  assert.equal(after.length, 1, 'the old row is reused, not duplicated')
  assert.equal(after[0].removed_at, undefined)
  assert.equal(after[0].masked_label, before.masked_label)
  assert.equal(after[0].role_in_group, before.role_in_group)
})

test('a reactivation whose old label is now taken answers 409 group_label_conflict', async (t) => {
  const request = await startMock(t)
  const path = `/api/admin/chat-groups/${MASKED_GROUP_ID}`
  const removed = (await request('GET', path)).body.group.members.find((m) => m.removed_at)

  const taken = await request('POST', `${path}/members`, {
    user_id: 105, role_in_group: 'volunteer', label: removed.masked_label.toUpperCase(),
  })
  const reactivated = await request('POST', `${path}/members`, { user_id: removed.user_id, role_in_group: 'donor', label: '' })

  assert.equal(taken.status, 200, 'a removed member does not hold on to their label')
  assert.equal(reactivated.status, 409)
  assert.equal(reactivated.body.code, 'group_label_conflict')
})

test('deciding a connect request twice answers 409 connect_request_decided; a missing one is an uncoded 404', async (t) => {
  const request = await startMock(t)
  const all = (await request('GET', '/api/admin/chat-groups/connect-requests')).body.items
  const approved = all.find((r) => r.status === 'approved')
  const declined = all.find((r) => r.status === 'declined')
  const body = {
    kind: 'masked', member_title: '', members: [{ user_id: approved.requester_user_id, role_in_group: 'donor', label: '' }],
  }

  const approveAgain = await request('POST', `/api/admin/chat-groups/connect-requests/${approved.id}/approve`, body)
  const declineAgain = await request('POST', `/api/admin/chat-groups/connect-requests/${declined.id}/decline`, { reason: 'Again' })
  const missing = await request('GET', '/api/admin/chat-groups/connect-requests/999999')

  for (const reply of [approveAgain, declineAgain]) {
    assert.equal(reply.status, 409)
    assert.equal(reply.body.code, 'connect_request_decided')
  }
  assert.deepEqual(missing, { status: 404, body: { success: false, error: 'Connect request not found.' } })
})

// ─── The connect-request inbox (Phase 6c, OPOS #26400) ───────────────────

test('connect requests carry requester_name for a requester with a profile, and omit the key otherwise', async (t) => {
  const request = await startMock(t)
  const named = new Map(ADMIN_USERS.map((u) => [u.user_id, u.profile?.full_name ?? null]))

  const { body } = await request('GET', '/api/admin/chat-groups/connect-requests')
  const one = await request('GET', `/api/admin/chat-groups/connect-requests/${body.items[0].id}`)

  assert.ok(body.items.some((item) => 'requester_name' in item), 'at least one requester is named')
  for (const item of body.items) {
    const name = named.get(item.requester_user_id)
    if (name) assert.equal(item.requester_name, name)
    else assert.ok(!('requester_name' in item), `request ${item.id} has no requester_name key`)
  }
  assert.equal(one.body.request.requester_name, body.items[0].requester_name)
})

test('approving a pending request opens its group; declining one records the trimmed reason', async (t) => {
  const request = await startMock(t)
  const pending = (await request('GET', '/api/admin/chat-groups/connect-requests?status=pending')).body.items
  const [toApprove, toDecline] = pending
  const body = {
    kind: 'masked', member_title: '', members: [{ user_id: toApprove.requester_user_id, role_in_group: 'donor', label: '' }],
  }
  const base = '/api/admin/chat-groups/connect-requests'

  const approved = await request('POST', `${base}/${toApprove.id}/approve`, body)
  const declined = await request('POST', `${base}/${toDecline.id}/decline`, { reason: '  Not this time.  ' })
  const approvedDetail = await request('GET', `${base}/${toApprove.id}`)
  const declinedDetail = await request('GET', `${base}/${toDecline.id}`)
  const blank = await request('POST', `${base}/${toDecline.id}/decline`, { reason: '  ' })

  assert.equal(approved.status, 200)
  assert.equal(approvedDetail.body.request.status, 'approved')
  assert.equal(approvedDetail.body.request.group_id, approved.body.group_id)
  assert.equal(declined.status, 200)
  assert.equal(declinedDetail.body.request.status, 'declined')
  assert.equal(declinedDetail.body.request.decline_reason, 'Not this time.')
  assert.equal(blank.status, 400)
})

test('approving without the requester among the members is 400 group_invalid_input', async (t) => {
  const request = await startMock(t)
  const [pending] = (await request('GET', '/api/admin/chat-groups/connect-requests?status=pending')).body.items
  const stranger = ADMIN_USERS.find((u) => u.user_id !== pending.requester_user_id && u.user_id !== GUEST_USER_ID)

  const reply = await request('POST', `/api/admin/chat-groups/connect-requests/${pending.id}/approve`, {
    kind: 'masked', member_title: '', members: [{ user_id: stranger.user_id, role_in_group: 'donor', label: '' }],
  })

  assert.equal(reply.status, 400)
  assert.equal(reply.body.code, 'group_invalid_input')
})
