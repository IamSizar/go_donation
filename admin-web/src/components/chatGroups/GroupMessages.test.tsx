/**
 * GroupMessages.test.tsx — the staff view of one chat group's conversation
 * (Phase 6b, OPOS #26399).
 *
 * Pins, through the real components and strings with a mocked `api`:
 *   - loading → content: real names, with a masked member's label and role;
 *     a staff message named as staff;
 *   - the empty state, and a failed load that recovers through Try again;
 *   - the poll: a new message arrives without a reload (only setInterval is
 *     faked, as in StaffChatPage.test.tsx, so waitFor keeps real timers);
 *   - the composer: sends, clears and refreshes; a refusal is shown in words
 *     and the draft is kept; hidden without messages:add, and replaced by the
 *     lifecycle notice when the group is paused or ended.
 */
import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import GroupMessages from './GroupMessages'
import { GROUP_POLL_INTERVAL_MS } from '../../lib/chatGroupDetail'
import type { ChatGroupDetail, ChatGroupMessage } from '../../lib/chatGroupsApi'
import { detailOf, messagesAfter, messagesUrl, refusal } from '../../test/chatGroupDetailKit'
import { CHAT_GROUP_MESSAGES, MASKED_GROUP_ID } from '../../test/fixtures/chatGroups'
import { mockApi } from '../../test/mockApi'
import { renderWithProviders } from '../../test/render'

const MESSAGES = CHAT_GROUP_MESSAGES[MASKED_GROUP_ID]
const URL = messagesUrl(MASKED_GROUP_ID)

const LATE: ChatGroupMessage = {
  id: 8199,
  sender_member_id: 702,
  sender_user_id: 103,
  sender_name: 'Sara Ali',
  body: 'The supplies arrived, thank you.',
  created_at: '2026-09-13T08:00:00Z',
}

afterEach(() => {
  vi.useRealTimers()
})

function renderMessages(patch: Partial<ChatGroupDetail> = {}, canSend = true) {
  const group = detailOf(MASKED_GROUP_ID, patch)
  return renderWithProviders(<GroupMessages group={group} canSend={canSend} />)
}

describe('GroupMessages — reading', () => {
  it('shows a skeleton, then every message with real names, labels and roles', async () => {
    mockApi().on('get', URL, messagesAfter(MESSAGES))

    const { container } = renderMessages()

    expect(screen.getByRole('status', { name: 'Loading messages…' })).toBeInTheDocument()
    expect(container.querySelectorAll('.skeleton-line').length).toBeGreaterThan(0)
    const list = await screen.findByRole('list', { name: 'Group messages' })
    const items = within(list).getAllByRole('listitem')
    expect(items).toHaveLength(MESSAGES.length)
    expect(within(items[0]).getByText('Layla Hassan')).toBeInTheDocument()
    expect(within(items[0]).getByText('Donor 1 · Grantor')).toBeInTheDocument()
    expect(within(items[2]).getByText('Rana Aziz')).toBeInTheDocument()
    expect(within(items[2]).getByText('Staff')).toBeInTheDocument()
  })

  it('shows a designed empty state when nobody has written yet', async () => {
    mockApi().on('get', URL, messagesAfter([]))

    renderMessages()

    expect(await screen.findByText('No messages yet. Messages from members and staff appear here.')).toBeInTheDocument()
  })

  it('recovers from a failed load through Try again', async () => {
    const user = userEvent.setup()
    const api = mockApi().on('get', URL, { status: 500, data: { success: false, error: 'Database error.' } })
    renderMessages()
    expect(await screen.findByText('A server error occurred. Please try again in a moment.')).toBeInTheDocument()

    api.on('get', URL, messagesAfter(MESSAGES))
    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(await screen.findByText(MESSAGES[0].body)).toBeInTheDocument()
  })

  it('adds a message the poll delivers, asking only for what is newer', async () => {
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] })
    const api = mockApi().on('get', URL, messagesAfter(MESSAGES))
    renderMessages()
    expect(await screen.findByText(MESSAGES[0].body)).toBeInTheDocument()

    api.on('get', URL, messagesAfter([...MESSAGES, LATE]))
    await act(async () => {
      vi.advanceTimersByTime(GROUP_POLL_INTERVAL_MS)
    })

    expect(await screen.findByText(LATE.body)).toBeInTheDocument()
    const last = api.callsTo('get', URL).at(-1)
    expect(last?.params).toMatchObject({ after_id: MESSAGES.at(-1)?.id })
    expect(screen.getAllByText(MESSAGES[0].body)).toHaveLength(1)
  })
})

describe('GroupMessages — the composer', () => {
  it('sends the trimmed message, clears the box and shows the message', async () => {
    const user = userEvent.setup()
    const api = mockApi()
      .on('get', URL, messagesAfter(MESSAGES))
      .on('post', URL, () => {
        api.on('get', URL, messagesAfter([...MESSAGES, { ...LATE, body: 'On my way' }]))
        return { data: { success: true, message_id: LATE.id } }
      })
    renderMessages()
    const box = await screen.findByRole('textbox', { name: 'Message to the group' })
    expect(screen.getByRole('button', { name: 'Send' })).toBeDisabled()

    await user.type(box, '  On my way  ')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    expect(await screen.findByText('On my way')).toBeInTheDocument()
    expect(api.callsTo('post', URL)[0].data).toEqual({ body: 'On my way' })
    expect(box).toHaveValue('')
  })

  it('shows a contact-details refusal in words and keeps the draft', async () => {
    const user = userEvent.setup()
    mockApi().on('get', URL, messagesAfter(MESSAGES)).on('post', URL, refusal(422, 'contact_details_blocked'))
    renderMessages()
    const box = await screen.findByRole('textbox', { name: 'Message to the group' })

    await user.type(box, 'Call 07701234567')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'This message contains a phone number or email address, so it was not sent.',
    )
    expect(box).toHaveValue('Call 07701234567')
  })

  it('shows the lifecycle refusal with the reason staff gave', async () => {
    const user = userEvent.setup()
    mockApi()
      .on('get', URL, messagesAfter(MESSAGES))
      .on('post', URL, refusal(409, 'chat_lifecycle_closed', { lifecycle_reason: 'Under review' }))
    renderMessages()

    await user.type(await screen.findByRole('textbox', { name: 'Message to the group' }), 'Hello')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('Participants are being shown: Under review')
  })

  it('hides the composer from staff without messages:add and says why', async () => {
    mockApi().on('get', URL, messagesAfter(MESSAGES))

    renderMessages({}, false)

    expect(await screen.findByText(MESSAGES[0].body)).toBeInTheDocument()
    expect(screen.queryByRole('textbox', { name: 'Message to the group' })).not.toBeInTheDocument()
    expect(screen.getByText('Your access level can read this group but not send messages to it.')).toBeInTheDocument()
  })

  it('replaces the composer with the paused notice and its reason', async () => {
    mockApi().on('get', URL, messagesAfter(MESSAGES))

    renderMessages({ lifecycle: 'paused', lifecycle_reason: 'Checking the delivery' })

    expect(await screen.findByText(MESSAGES[0].body)).toBeInTheDocument()
    expect(screen.queryByRole('textbox', { name: 'Message to the group' })).not.toBeInTheDocument()
    const note = screen.getByRole('note')
    expect(note).toHaveTextContent('This group is paused, so nobody can send messages. Resume it to write here.')
    expect(note).toHaveTextContent('Participants are being shown: Checking the delivery')
  })

  it('replaces the composer with the ended notice', async () => {
    mockApi().on('get', URL, messagesAfter(MESSAGES))

    renderMessages({ lifecycle: 'ended' })

    await waitFor(() =>
      expect(screen.getByRole('note')).toHaveTextContent('This group has ended. Its history stays readable'),
    )
    expect(screen.queryByRole('button', { name: 'Send' })).not.toBeInTheDocument()
  })
})
