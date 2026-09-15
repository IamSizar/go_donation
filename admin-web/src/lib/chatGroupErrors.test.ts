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
import { AxiosError, AxiosHeaders, type AxiosResponse } from 'axios'
import { describe, expect, it } from 'vitest'
import {
  CHAT_GROUP_ERROR_CODES,
  CHAT_GROUP_ERROR_KEYS,
  chatGroupErrorArea,
  chatGroupErrorCode,
  describeChatGroupError,
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
      'connect_context_not_found',
      'connect_request_decided',
      'group_invalid_input',
      'group_label_conflict',
      'group_label_contact',
      'group_member_conflict',
      'group_not_found',
      'guest_member_not_allowed',
      'not_group_member',
      'sensitive_data_required',
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
    const err = refused(409, { success: false, error: 'Duplicate label.', code: 'group_label_conflict' })

    expect(chatGroupErrorCode(err)).toBe('group_label_conflict')
    expect(describeChatGroupError(err)).toBe(
      'Two members would have the same label. Give each member a different label.',
    )
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

  it('never shows the prose of a 5xx', () => {
    expect(describeChatGroupError(refused(500, { success: false, error: 'Database error.' }))).toBe(
      'A server error occurred. Please try again in a moment.',
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
