/**
 * connectRequestForm.test.ts — the pure rules behind the connect-request
 * inbox's Approve and Decline dialogs (Phase 6c, OPOS #26400).
 *
 * Pins: the decline reason is trimmed, required and capped; the approve draft
 * starts with the requester as its first member (ApproveConnectRequest refuses
 * a body without them); and the rule that the requester may not be removed.
 */
import { describe, expect, it } from 'vitest'
import {
  DECLINE_REASON_MAX_LENGTH,
  approveDraftFor,
  requesterIssue,
  validateDeclineReason,
} from './connectRequestForm'
import type { ConnectRequest } from './chatGroupsApi'

const REQUEST: ConnectRequest = {
  id: 31,
  requester_user_id: 102,
  context_type: 'case',
  context_id: 2291,
  message: 'I would like to support this family directly.',
  status: 'pending',
  created_at: '2026-09-15T08:30:00Z',
  context_label: 'Case HC-2291',
}

describe('validateDeclineReason', () => {
  it('requires a reason that is not only whitespace', () => {
    expect(validateDeclineReason('   ')).toEqual({ key: 'chat_groups.inbox.decline.reason_required' })
  })

  it('refuses a reason longer than the limit after trimming', () => {
    const tooLong = 'a'.repeat(DECLINE_REASON_MAX_LENGTH + 1)
    expect(validateDeclineReason(tooLong)).toEqual({
      key: 'chat_groups.inbox.decline.reason_too_long',
      vars: { max: DECLINE_REASON_MAX_LENGTH },
    })
  })

  it('accepts a reason at the limit once surrounding spaces are trimmed', () => {
    expect(validateDeclineReason(`  ${'a'.repeat(DECLINE_REASON_MAX_LENGTH)}  `)).toBeUndefined()
  })
})

describe('approveDraftFor', () => {
  it('puts the requester in the first member row, named when the name was sent', () => {
    const draft = approveDraftFor({ ...REQUEST, requester_name: 'Sara Ali' })
    expect(draft.kind).toBeNull()
    expect(draft.members).toEqual([
      { key: 'm1', user: { user_id: 102, phone: '', role_id: null, full_name: 'Sara Ali' }, role: '', label: '' },
    ])
  })

  it('leaves the name empty when requester_name is absent', () => {
    expect(approveDraftFor(REQUEST).members[0].user?.full_name).toBeNull()
  })
})

describe('requesterIssue', () => {
  it('names the rule when no row holds the requester', () => {
    const draft = { ...approveDraftFor(REQUEST), members: [] }
    expect(requesterIssue(draft, 102)).toEqual({ key: 'chat_groups.inbox.approve.requester_required' })
  })

  it('is satisfied while the requester is still a member', () => {
    expect(requesterIssue(approveDraftFor(REQUEST), 102)).toBeUndefined()
  })
})
