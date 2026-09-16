/**
 * ChatGroupsPage.test.tsx — the Chat Groups list: every group staff can
 * supervise, and the way in to creating one.
 *
 * Pins the page's four async states through the real component, the real
 * i18n strings and a mocked `api`:
 *   - loading → content: a skeleton first, then one row per group with its
 *     kind badge, title, last message and time;
 *   - error → content: the translated server line, and a Retry button whose
 *     visible label is "Try again" (error.retry), never a raw i18n key;
 *   - empty: a designed empty state with a Create call to action;
 *   - permission: no Create button for staff without messages:add.
 *
 * Strings are asserted as literal English, as ContactBlocksPanel.test.tsx
 * explains: a missing key would otherwise pass on both sides.
 */
import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import ChatGroupsPage from './ChatGroupsPage'
import { formatDateParts } from '../lib/dates'
import { EMPLOYEE_USER, PERMISSIONS_URL, matrixWith, servePermissions } from '../test/chatGroupsKit'
import { CHAT_GROUP_SUMMARIES } from '../test/fixtures/chatGroups'
import { mockApi } from '../test/mockApi'
import { renderWithProviders } from '../test/render'

const LIST_URL = '/api/admin/chat-groups'
const SERVER_ERROR_LINE = 'A server error occurred. Please try again in a moment.'

describe('ChatGroupsPage', () => {
  it('shows a skeleton, then one row per group with its kind, title, last message and time', async () => {
    // Arrange
    const api = servePermissions(mockApi()).on('get', LIST_URL, {
      data: { success: true, items: CHAT_GROUP_SUMMARIES },
    })

    // Act
    const { container } = renderWithProviders(<ChatGroupsPage />)

    // Assert: the skeleton is on screen before the reply lands.
    expect(screen.getByRole('status', { name: 'Loading chat groups…' })).toBeInTheDocument()
    expect(container.querySelectorAll('.skeleton-line').length).toBeGreaterThan(0)

    const list = await screen.findByRole('list', { name: 'Chat groups' })
    expect(screen.queryByRole('status', { name: 'Loading chat groups…' })).not.toBeInTheDocument()
    const [team, masked] = within(list).getAllByRole('listitem')

    expect(within(team).getByText('Team')).toBeInTheDocument()
    expect(within(team).getByText('Distribution volunteers — Mosul')).toBeInTheDocument()
    expect(within(team).getByText('Thanks both. Report any shortages here.')).toBeInTheDocument()
    const teamTime = team.querySelector('time')
    expect(teamTime).toHaveAttribute('datetime', '2026-09-14T09:00:00Z')
    // Client item C3: the stamp is the shared DateCell — the date on top, the
    // time under it — not one combined line.
    const { date, time } = formatDateParts('2026-09-14T09:00:00Z')
    expect(Array.from(teamTime!.querySelectorAll('span')).map((s) => s.textContent)).toEqual([date, time])

    // A masked group has no title of its own, so it is named by its id.
    expect(within(masked).getByText('Masked')).toBeInTheDocument()
    expect(within(masked).getByText(/Masked group/)).toHaveTextContent('#T41')
    expect(within(masked).getByText('The office will confirm the delivery details here.')).toBeInTheDocument()

    // Every row opens its group (Phase 6b).
    expect(within(team).getByRole('link', { name: 'Distribution volunteers — Mosul' })).toHaveAttribute('href', '/chat-groups/42')
    expect(within(masked).getByRole('link', { name: /Masked group/ })).toHaveAttribute('href', '/chat-groups/41')

    expect(screen.getByRole('button', { name: 'New group' })).toBeInTheDocument()
    expect(api.callsTo('get', LIST_URL)).toEqual([{ method: 'get', url: LIST_URL }])
  })

  it('replaces a failed load with the list when the operator presses Try again', async () => {
    // Arrange: the first load fails with the backend's English prose, which
    // must not reach the operator.
    const user = userEvent.setup()
    const api = servePermissions(mockApi()).on('get', LIST_URL, {
      status: 500,
      data: { success: false, error: 'Database error.' },
    })
    renderWithProviders(<ChatGroupsPage />)
    expect(await screen.findByText(SERVER_ERROR_LINE)).toBeInTheDocument()
    expect(screen.queryByText('Database error.')).not.toBeInTheDocument()
    expect(screen.queryByText('common.retry')).not.toBeInTheDocument()

    // Act: the server recovers, then the operator retries.
    api.on('get', LIST_URL, { data: { success: true, items: CHAT_GROUP_SUMMARIES } })
    await user.click(screen.getByRole('button', { name: 'Try again' }))

    // Assert
    expect(await screen.findByText('Distribution volunteers — Mosul')).toBeInTheDocument()
    expect(screen.queryByText(SERVER_ERROR_LINE)).not.toBeInTheDocument()
    expect(api.callsTo('get', LIST_URL)).toHaveLength(2)
  })

  it('shows a designed empty state whose call to action opens the create dialog', async () => {
    // Arrange
    const user = userEvent.setup()
    servePermissions(mockApi()).on('get', LIST_URL, { data: { success: true, items: [] } })
    renderWithProviders(<ChatGroupsPage />)

    // Act
    expect(await screen.findByText('No chat groups yet')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Create a group' }))

    // Assert
    expect(await screen.findByRole('dialog', { name: 'New chat group' })).toBeInTheDocument()
  })

  it('hides every Create button from staff without messages:add', async () => {
    // Arrange: an employee whose matrix allows reading messages but not adding.
    const api = servePermissions(mockApi(), matrixWith({ messages: { add: false } })).on('get', LIST_URL, {
      data: { success: true, items: [] },
    })

    // Act
    renderWithProviders(<ChatGroupsPage />, { user: EMPLOYEE_USER })

    // Assert
    expect(await screen.findByText('No chat groups yet')).toBeInTheDocument()
    await waitFor(() => expect(api.callsTo('get', PERMISSIONS_URL).length).toBeGreaterThan(0))
    expect(
      screen.getByText('Your access level cannot create groups. A staff member who can add messages can create the first one.'),
    ).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'New group' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Create a group' })).not.toBeInTheDocument()
  })

  it('shows New group to an employee whose matrix allows messages:add', async () => {
    // Arrange: the tier alone would deny it, so only the matrix can allow it.
    servePermissions(mockApi(), matrixWith({ messages: { add: true } })).on('get', LIST_URL, {
      data: { success: true, items: CHAT_GROUP_SUMMARIES },
    })

    // Act
    renderWithProviders(<ChatGroupsPage />, { user: EMPLOYEE_USER })

    // Assert
    expect(await screen.findByRole('button', { name: 'New group' })).toBeInTheDocument()
  })
})
