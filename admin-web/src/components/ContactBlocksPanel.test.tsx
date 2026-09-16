/**
 * ContactBlocksPanel.test.tsx — the refused-contact log for one donor thread.
 *
 * Pins two of the panel's four async states through the real component, the
 * real i18n strings and a mocked `api`:
 *   - empty: a clean thread says "nothing was blocked", and the list was read
 *     from the donor-chat route for THIS thread;
 *   - error → content: a failed load shows the translated server-error line,
 *     and Retry loads the list again and replaces the error with it.
 *
 * Strings are asserted as literal English on purpose. Asserting translate()'s
 * output would pass even if a key went missing, because translate() and the
 * component would both fall back to the same raw key.
 */
import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import ContactBlocksPanel, { type ContactBlock } from './ContactBlocksPanel'
import { mockApi } from '../test/mockApi'
import { renderWithProviders } from '../test/render'

const BLOCKS_URL = '/api/admin/chats/7/contact-blocks'

/** One refusal, in the shape GET …/contact-blocks returns. */
const PHONE_BLOCK: ContactBlock = {
  id: 301,
  thread_id: 7,
  sender_user_id: 55,
  sender_name: 'Layla Hassan',
  kind: 'phone',
  match_count: 1,
  redacted_body: 'Call me on ••• after the delivery',
  created_at: '2026-09-14T09:30:00Z',
}

/** The panel's landmark, found by its visible heading. */
function panel(): HTMLElement {
  return screen.getByRole('region', { name: 'Blocked contact sharing' })
}

describe('ContactBlocksPanel', () => {
  it('shows the reassuring empty state when nothing in the thread was blocked', async () => {
    // Arrange
    const api = mockApi().on('get', BLOCKS_URL, { data: { success: true, items: [] } })

    // Act
    renderWithProviders(<ContactBlocksPanel threadId={7} />)

    // Assert
    expect(await screen.findByText('Nothing has been blocked in this conversation.')).toBeInTheDocument()
    expect(api.calls).toEqual([{ method: 'get', url: BLOCKS_URL }])
  })

  it('replaces a failed load with the list when the operator presses Retry', async () => {
    // Arrange: the first load fails with a 500 carrying the backend's English
    // prose, which describeError() must NOT show to the operator.
    const user = userEvent.setup()
    const api = mockApi().on('get', BLOCKS_URL, {
      status: 500,
      data: { success: false, error: 'Database error.' },
    })
    renderWithProviders(<ContactBlocksPanel threadId={7} />)
    expect(
      await screen.findByText('A server error occurred. Please try again in a moment.'),
    ).toBeInTheDocument()
    expect(screen.queryByText('Database error.')).not.toBeInTheDocument()

    // Act: the server recovers, then the operator retries. The button is found
    // by role rather than by its label: the component asks for `common.retry`,
    // which no locale file defines (only `error.retry` exists), so today it
    // renders the raw key. Pin the visible label here once that key exists.
    api.on('get', BLOCKS_URL, { data: { success: true, items: [PHONE_BLOCK] } })
    await user.click(within(panel()).getByRole('button'))

    // Assert
    expect(await screen.findByText('Call me on ••• after the delivery')).toBeInTheDocument()
    expect(within(panel()).getByText('1 blocked')).toBeInTheDocument()
    expect(within(panel()).getByText('Phone number')).toBeInTheDocument()
    expect(
      screen.queryByText('A server error occurred. Please try again in a moment.'),
    ).not.toBeInTheDocument()
    expect(api.callsTo('get', BLOCKS_URL)).toHaveLength(2)
  })
})
