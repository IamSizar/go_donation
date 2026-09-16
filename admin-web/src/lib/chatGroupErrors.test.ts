/**
 * chatGroupErrors.test.ts — how a refused chat-group request is put into
 * words for the operator.
 *
 * Pins three things:
 *   - every code the chat-group routes send has a message in English AND in
 *     Arabic, so no refusal reaches an Arabic screen as the server's English;
 *   - the fallbacks, in order: translated code → the server's own text for a
 *     4xx → a generic translated line;
 *   - which refusals belong beside the member rows rather than atop the form.
 */
import axios, { AxiosError, AxiosHeaders, type AxiosResponse } from 'axios'
import { describe, expect, it, vi } from 'vitest'
import { DELETE_CANCELLED } from './api'
import {
  CHAT_GROUP_ERROR_CODES,
  CHAT_GROUP_ERROR_KEYS,
  chatGroupErrorArea,
  chatGroupErrorCode,
  describeChatGroupError,
  describeConnectRequestError,
} from './chatGroupErrors'
import { translate } from './i18n'

/** An axios failure carrying `status` and `data`, as a real refused request does. */
function refused(status: number, data: unknown): AxiosError {
  const config = { headers: new AxiosHeaders() }
  const response: AxiosResponse = { data, status, statusText: '', headers: {}, config }
  const code = status >= 500 ? AxiosError.ERR_BAD_RESPONSE : AxiosError.ERR_BAD_REQUEST
  return new AxiosError(`Request failed with status code ${status}`, code, config, null, response)
}

describe('CHAT_GROUP_ERROR_KEYS', () => {
  it('covers every code the chat-group routes send', () => {
    expect([...CHAT_GROUP_ERROR_CODES].sort()).toEqual([
      'chat_lifecycle_closed',
      'connect_context_not_found',
      'connect_request_decided',
      'connect_request_not_found',
      'contact_details_blocked',
      'group_invalid_input',
      'group_label_conflict',
      'group_label_contact',
      'group_member_conflict',
      'group_not_found',
      'guest_member_not_allowed',
      'not_group_member',
      'sensitive_data_required',
      'server_error',
      'team_member_role_not_allowed',
      'unauthorized',
    ])
  })

  it.each([...CHAT_GROUP_ERROR_CODES])('has an English and an Arabic message for %s', (code) => {
    const key = CHAT_GROUP_ERROR_KEYS[code]
    const english = translate(key, undefined, 'en')
    const arabic = translate(key, undefined, 'ar')

    expect(english).not.toBe(key)
    expect(arabic).not.toBe(key)
    // translate() falls back to English for a key Arabic lacks, so an equal
    // string means the Arabic entry is missing.
    expect(arabic).not.toBe(english)
  })
})

describe('describeChatGroupError', () => {
  it("translates a known code instead of showing the server's English", () => {
    const err = refused(409, {
      success: false,
      error: 'Another member of this group already has this label.',
      code: 'group_label_conflict',
    })

    expect(chatGroupErrorCode(err)).toBe('group_label_conflict')
    expect(describeChatGroupError(err)).toBe(
      "Another member of this group already has this label. Each member's label must be different.",
    )
  })

  it('adds the reason staff gave when a paused or ended group refuses a message', () => {
    const err = refused(409, {
      success: false,
      error: 'This conversation has been paused by our team. Reason: Under review',
      code: 'chat_lifecycle_closed',
      lifecycle: 'paused',
      lifecycle_reason: 'Under review',
    })

    expect(describeChatGroupError(err)).toBe(
      'This group is paused or has ended, so no new messages can be sent. Participants are being shown: Under review',
    )
  })

  it('says only that the group is closed when staff gave no reason', () => {
    const err = refused(409, { success: false, error: 'Closed.', code: 'chat_lifecycle_closed', lifecycle_reason: '  ' })

    expect(describeChatGroupError(err)).toBe('This group is paused or has ended, so no new messages can be sent.')
  })

  it('explains a message refused for carrying contact details', () => {
    const err = refused(422, { success: false, error: 'Contact details are not allowed.', code: 'contact_details_blocked' })

    expect(describeChatGroupError(err)).toBe(
      'This message contains a phone number or email address, so it was not sent. Remove the contact detail and send it again.',
    )
  })

  it('asks the operator to sign in again on a 401 unauthorized (#26496)', () => {
    const err = refused(401, { success: false, error: 'Unauthorized.', code: 'unauthorized' })

    expect(chatGroupErrorCode(err)).toBe('unauthorized')
    // Reuses the existing error.auth_required wording, in the operator's language.
    expect(describeChatGroupError(err)).toBe('Your session has ended. Please sign in again.')
    expect(describeChatGroupError(err)).not.toBe('Unauthorized.')
  })

  it('shows the generic server line for server_error, never "Database error."', () => {
    const err = refused(500, { success: false, error: 'Database error.', code: 'server_error' })

    expect(describeChatGroupError(err)).toBe('A server error occurred. Please try again in a moment.')
  })

  it("falls back to the server's own text for a 4xx with no code it knows", () => {
    expect(describeChatGroupError(refused(400, { success: false, error: 'Invalid request.' }))).toBe('Invalid request.')
    expect(
      describeChatGroupError(refused(400, { success: false, error: 'Nope.', code: 'brand_new_code' })),
    ).toBe('Nope.')
  })

  it('falls back to the generic line when a 4xx carries no text at all', () => {
    expect(describeChatGroupError(refused(400, {}))).toBe('Something went wrong. Please try again.')
  })

  it("never shows a programming error's own message, and logs it instead", () => {
    // Arrange: the kind of guard buildCreateGroupBody throws on a caller bug.
    const logged = vi.spyOn(console, 'error').mockImplementation(() => {})
    const bug = new Error('buildCreateGroupBody: member row m2 has no person')

    // Act
    const shown = describeChatGroupError(bug)

    // Assert
    expect(shown).toBe('Something went wrong. Please try again.')
    expect(logged).toHaveBeenCalledWith(expect.any(String), bug)
  })

  it('keeps the plain "delete cancelled" line when the operator dismisses the password prompt', () => {
    expect(describeChatGroupError(new axios.Cancel(DELETE_CANCELLED))).toBe('Delete cancelled — nothing was deleted.')
  })

  it('never shows the prose of a 5xx', () => {
    expect(describeChatGroupError(refused(500, { success: false, error: 'Database error.' }))).toBe(
      'A server error occurred. Please try again in a moment.',
    )
  })
})

describe('describeConnectRequestError', () => {
  it('translates the uncoded 404 a missing connect request answers', () => {
    const err = refused(404, { success: false, error: 'Connect request not found.' })

    expect(describeConnectRequestError(err)).toBe(
      'This connect request no longer exists. Refresh the list to see the current requests.',
    )
  })

  it('translates the coded 404 (#26478) through either helper', () => {
    const err = refused(404, { success: false, error: 'Connect request not found.', code: 'connect_request_not_found' })

    expect(chatGroupErrorCode(err)).toBe('connect_request_not_found')
    for (const describe of [describeConnectRequestError, describeChatGroupError]) {
      expect(describe(err)).toBe('This connect request no longer exists. Refresh the list to see the current requests.')
    }
  })

  it('still prefers a code the server sent', () => {
    const err = refused(409, { success: false, error: 'This request has already been decided.', code: 'connect_request_decided' })

    expect(describeConnectRequestError(err)).toBe(
      'Another staff member has already decided this request. Refresh the list to see the outcome.',
    )
  })
})

describe('chatGroupErrorArea', () => {
  it('puts refusals about who is in the group, or their labels, beside the members', () => {
    for (const code of ['guest_member_not_allowed', 'group_member_conflict', 'group_label_conflict', 'group_label_contact']) {
      expect(chatGroupErrorArea(refused(400, { code }))).toBe('members')
    }
  })

  it('puts every other failure at the top of the form', () => {
    expect(chatGroupErrorArea(refused(400, { code: 'group_invalid_input' }))).toBe('form')
    expect(chatGroupErrorArea(refused(500, { error: 'Database error.' }))).toBe('form')
    expect(chatGroupErrorArea(new Error('offline'))).toBe('form')
  })
})
