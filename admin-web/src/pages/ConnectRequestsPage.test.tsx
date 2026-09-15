/**
 * ConnectRequestsPage.test.tsx — the connect-request inbox (Phase 6c, OPOS #26400).
 *
 * Pins, through the real page, the real i18n strings and a mocked `api`:
 *   - loading → content: a skeleton, then one row per request with requester,
 *     context, message preview, status badge and time;
 *   - the requester fallback ("Requester #T…") when `requester_name` is absent;
 *   - the status filter: pending by default, ?status= sent on change, and a
 *     designed empty state per filter;
 *   - error → retry;
 *   - the detail panel: the full message, the decline reason and the group
 *     link on decided requests, never target_hint (D8);
 *   - gates: Approve and Decline only on pending requests, and only with
 *     messages:edit.
 *   - after a decision (OPOS #26493): the panel stays on the request with its
 *     new status and no decision buttons, even though the row left the list
 *     and without depending on a refetch of the detail.
 */
import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import ConnectRequestsPage from './ConnectRequestsPage'
import { chooseRole, matrixWith, servePermissions, serveUserSearch } from '../test/chatGroupsKit'
import { CONNECT_REQUESTS } from '../test/fixtures/chatGroups'
import { mockApi, type MockApi } from '../test/mockApi'
import { renderWithProviders } from '../test/render'

const LIST_URL = '/api/admin/chat-groups/connect-requests'
const APPROVE_URL = '/api/admin/chat-groups/connect-requests/31/approve'
const DETAIL_URL = /^\/api\/admin\/chat-groups\/connect-requests\/\d+$/

/** Serves the list filtered by ?status=, and each request's detail by id. */
function serveInbox(api: MockApi, items = CONNECT_REQUESTS): MockApi {
  return api
    .on('get', LIST_URL, (call) => {
      const status = (call.params as { status?: string } | undefined)?.status
      return { data: { success: true, items: items.filter((r) => !status || r.status === status) } }
    })
    .on('get', DETAIL_URL, (call) => {
      const found = items.find((r) => call.url.endsWith(`/${r.id}`))
      if (!found) return { status: 404, data: { success: false, error: 'Connect request not found.' } }
      return { data: { success: true, request: found, context_label: found.context_label } }
    })
}

const DECLINE_URL = '/api/admin/chat-groups/connect-requests/31/decline'
const ROW_NAME = /I would like to support this family/

/**
 * An inbox whose request #31 can be decided. After decide(), the list drops it
 * from Pending and its detail route fails, so the panel can only show the
 * outcome from the decision itself.
 */
function serveDecidingInbox(): MockApi {
  return serveInbox(serveUserSearch(servePermissions(mockApi())))
}

/** Plays the server after a decision on #31: gone from the list, detail failing. */
function decide(api: MockApi): void {
  serveInbox(api, CONNECT_REQUESTS.filter((r) => r.id !== 31))
  api.on('get', DETAIL_URL, { status: 500, data: { success: false, error: 'Database error.' } })
}

/** Opens request #31 from the Pending list and returns its panel. */
async function openPendingRequest(user: ReturnType<typeof userEvent.setup>): Promise<HTMLElement> {
  await user.click(await screen.findByRole('button', { name: ROW_NAME }))
  return screen.findByRole('region', { name: 'Request details' })
}

const NAMED = CONNECT_REQUESTS.map((r) => (r.id === 31 ? { ...r, requester_name: 'Sara Ali' } : r))

describe('ConnectRequestsPage', () => {
  it('shows a skeleton, then the pending requests with requester, context, message and status', async () => {
    const api = serveInbox(servePermissions(mockApi()), NAMED)

    renderWithProviders(<ConnectRequestsPage />)

    expect(screen.getByRole('status', { name: 'Loading connect requests…' })).toBeInTheDocument()
    const list = await screen.findByRole('list', { name: 'Connect requests' })
    const rows = within(list).getAllByRole('listitem')
    expect(rows).toHaveLength(2)
    // #32 has no requester_name: the translated fallback, never "undefined".
    expect(within(rows[0]).getByText(/Requester/)).toHaveTextContent('#T105')
    expect(within(rows[1]).getByText('Sara Ali')).toBeInTheDocument()
    expect(within(rows[1]).getByText('Case HC-2291 — School supplies for three children')).toBeInTheDocument()
    expect(within(rows[1]).getByText('I would like to support this family directly.')).toBeInTheDocument()
    expect(within(rows[1]).getByText('Pending')).toBeInTheDocument()
    expect(rows[1].querySelector('time')).toHaveAttribute('datetime', '2026-09-15T08:30:00Z')
    expect(api.callsTo('get', LIST_URL)).toEqual([{ method: 'get', url: LIST_URL, params: { status: 'pending' } }])
  })

  it('asks for the chosen status and shows that filter’s empty state', async () => {
    const user = userEvent.setup()
    const api = serveInbox(servePermissions(mockApi()), CONNECT_REQUESTS.filter((r) => r.status !== 'declined'))
    renderWithProviders(<ConnectRequestsPage />)
    await screen.findByRole('list', { name: 'Connect requests' })

    await user.click(screen.getByRole('button', { name: 'Declined' }))

    expect(await screen.findByText('No declined requests')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Declined' })).toHaveAttribute('aria-pressed', 'true')
    expect(api.callsTo('get', LIST_URL).at(-1)?.params).toEqual({ status: 'declined' })
  })

  it('replaces a failed load with the list when the operator presses Try again', async () => {
    const user = userEvent.setup()
    const api = servePermissions(mockApi()).on('get', LIST_URL, {
      status: 500,
      data: { success: false, error: 'Database error.' },
    })
    renderWithProviders(<ConnectRequestsPage />)

    expect(await screen.findByRole('alert')).toHaveTextContent('A server error occurred. Please try again in a moment.')
    expect(screen.queryByText('Database error.')).not.toBeInTheDocument()
    serveInbox(api)
    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(await screen.findByRole('list', { name: 'Connect requests' })).toBeInTheDocument()
  })

  it('opens a declined request with its reason and no actions, and never shows target_hint', async () => {
    const user = userEvent.setup()
    serveInbox(servePermissions(mockApi()))
    renderWithProviders(<ConnectRequestsPage />)
    await screen.findByRole('list', { name: 'Connect requests' })
    await user.click(screen.getByRole('button', { name: 'Declined' }))

    await user.click(await screen.findByRole('button', { name: /Please give them my phone number/ }))

    const panel = await screen.findByRole('region', { name: 'Request details' })
    expect(await within(panel).findByText(/We cannot share contact details/)).toBeInTheDocument()
    expect(within(panel).queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument()
    expect(within(panel).queryByRole('button', { name: 'Decline' })).not.toBeInTheDocument()
    expect(panel).not.toHaveTextContent('103')
  })

  it('links an approved request to its group', async () => {
    const user = userEvent.setup()
    serveInbox(servePermissions(mockApi()))
    renderWithProviders(<ConnectRequestsPage />)
    await screen.findByRole('list', { name: 'Connect requests' })
    await user.click(screen.getByRole('button', { name: 'Approved' }))

    await user.click(await screen.findByRole('button', { name: /Could I speak with the family/ }))

    const panel = await screen.findByRole('region', { name: 'Request details' })
    const link = await within(panel).findByRole('link', { name: /Open the group/ })
    expect(link).toHaveAttribute('href', '/chat-groups/41')
  })

  it('offers Approve and Decline on a pending request to staff with messages:edit', async () => {
    const user = userEvent.setup()
    serveInbox(servePermissions(mockApi()))
    renderWithProviders(<ConnectRequestsPage />)

    await user.click(await screen.findByRole('button', { name: /I can deliver the wheelchair/ }))

    const panel = await screen.findByRole('region', { name: 'Request details' })
    expect(await within(panel).findByRole('button', { name: 'Approve' })).toBeInTheDocument()
    expect(within(panel).getByRole('button', { name: 'Decline' })).toBeInTheDocument()
  })

  it('hides Approve and Decline from staff without messages:edit', async () => {
    const user = userEvent.setup()
    serveInbox(servePermissions(mockApi(), matrixWith({ messages: { edit: false } })))
    renderWithProviders(<ConnectRequestsPage />)

    await user.click(await screen.findByRole('button', { name: /I can deliver the wheelchair/ }))

    const panel = await screen.findByRole('region', { name: 'Request details' })
    await within(panel).findByText('I can deliver the wheelchair myself if that helps.')
    await waitFor(() => expect(within(panel).queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument())
    expect(within(panel).queryByRole('button', { name: 'Decline' })).not.toBeInTheDocument()
  })

  it('keeps the approved request open with Approved and its group link, without refetching it', async () => {
    const user = userEvent.setup()
    const api = serveDecidingInbox()
    api.on('post', APPROVE_URL, () => {
      decide(api)
      return { data: { success: true, group_id: 100010 } }
    })
    renderWithProviders(<ConnectRequestsPage />)

    const panel = await openPendingRequest(user)
    await user.click(await within(panel).findByRole('button', { name: 'Approve' }))
    await user.click(screen.getByRole('radio', { name: /Masked group/ }))
    await chooseRole(user, 1, 'donor')
    await user.click(screen.getByRole('button', { name: 'Approve and open group' }))

    // The row has left the Pending list, but the panel stays on the request.
    await waitFor(() => expect(screen.queryByRole('button', { name: ROW_NAME })).not.toBeInTheDocument())
    const decided = screen.getByRole('region', { name: 'Request details' })
    expect(await within(decided).findByRole('link', { name: /Open the group/ })).toHaveAttribute('href', '/chat-groups/100010')
    expect(within(decided).getByText('Approved')).toBeInTheDocument()
    expect(within(decided).queryByRole('alert')).not.toBeInTheDocument()
    expect(within(decided).queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument()
    expect(within(decided).queryByRole('button', { name: 'Decline' })).not.toBeInTheDocument()
  })

  it('keeps the declined request open with Declined and the reason given', async () => {
    const user = userEvent.setup()
    const api = serveDecidingInbox()
    api.on('post', DECLINE_URL, () => {
      decide(api)
      return { data: { success: true } }
    })
    renderWithProviders(<ConnectRequestsPage />)

    const panel = await openPendingRequest(user)
    await user.click(await within(panel).findByRole('button', { name: 'Decline' }))
    await user.type(screen.getByRole('textbox', { name: 'Reason' }), 'The case is already fully funded.')
    await user.click(screen.getByRole('button', { name: 'Decline request' }))

    await waitFor(() => expect(screen.queryByRole('button', { name: ROW_NAME })).not.toBeInTheDocument())
    const decided = screen.getByRole('region', { name: 'Request details' })
    expect(await within(decided).findByText('The case is already fully funded.')).toBeInTheDocument()
    expect(within(decided).getByText('Declined')).toBeInTheDocument()
    expect(within(decided).queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument()
  })

  it('moves on from a decided request when the filter changes', async () => {
    const user = userEvent.setup()
    serveInbox(servePermissions(mockApi()))
    renderWithProviders(<ConnectRequestsPage />)
    await user.click(await screen.findByRole('button', { name: /I would like to support this family/ }))
    await screen.findByRole('region', { name: 'Request details' })

    await user.click(screen.getByRole('button', { name: 'Declined' }))

    expect(screen.queryByRole('region', { name: 'Request details' })).not.toBeInTheDocument()
  })

  it('says so, translated, when the opened request no longer exists', async () => {
    const user = userEvent.setup()
    const api = serveInbox(servePermissions(mockApi()))
    renderWithProviders(<ConnectRequestsPage />)
    const row = await screen.findByRole('button', { name: /I can deliver the wheelchair/ })
    api.on('get', DETAIL_URL, { status: 404, data: { success: false, error: 'Connect request not found.' } })

    await user.click(row)

    const panel = await screen.findByRole('region', { name: 'Request details' })
    expect(await within(panel).findByRole('alert')).toHaveTextContent('This connect request no longer exists.')
  })
})
