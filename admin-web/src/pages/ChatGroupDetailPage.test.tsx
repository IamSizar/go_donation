/**
 * ChatGroupDetailPage.test.tsx — /chat-groups/:id, one chat group for staff
 * (Phase 6b, OPOS #26399).
 *
 * Pins the page shell through the real components and strings with a mocked
 * `api`; the roster, messages and contact-block panels have their own tests:
 *   - loading → content: a skeleton, then the header (kind, name, lifecycle)
 *     and every panel;
 *   - 403 sensitive_data_required: a designed permission state, not an error;
 *   - 404 and 500: the translated reason, Try again and the way back;
 *   - lifecycle: ChatLifecycleControls for messages:edit, a read-only state
 *     (with the reason and archived flag) without it; a trashed group goes
 *     back to the list;
 *   - export (E3): the rows the file receives carry masked_label and
 *     role_in_group.
 */
import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { Route, Routes } from 'react-router-dom'
import ChatGroupDetailPage from './ChatGroupDetailPage'
import { downloadCsv } from '../lib/csv'
import { askForText, askToConfirm } from '../lib/dialogs'
import { EMPLOYEE_USER, matrixWith, servePermissions, serveUserSearch } from '../test/chatGroupsKit'
import { detailOf, detailReply, groupUrl, messagesUrl, refusal, serveGroup } from '../test/chatGroupDetailKit'
import { MASKED_GROUP_ID, TEAM_GROUP_ID } from '../test/fixtures/chatGroups'
import { mockApi, type MockApi } from '../test/mockApi'
import type { StoredUser } from '../lib/api'
import { renderWithProviders } from '../test/render'

vi.mock('../lib/csv', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/csv')>()),
  downloadCsv: vi.fn(),
  downloadExcel: vi.fn(),
  downloadPdf: vi.fn(),
  downloadWord: vi.fn(),
}))

vi.mock('../lib/dialogs', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/dialogs')>()),
  askForText: vi.fn(),
  askToConfirm: vi.fn(),
}))

beforeEach(() => {
  vi.mocked(askForText).mockReset()
  vi.mocked(askToConfirm).mockReset()
  vi.mocked(downloadCsv).mockReset()
})

/** Mounts the page at /chat-groups/:id, with a stand-in list page to go back to. */
function renderPage(id: number, user?: StoredUser) {
  return renderWithProviders(
    <Routes>
      <Route path="/chat-groups/:id" element={<ChatGroupDetailPage />} />
      <Route path="/chat-groups" element={<p>The list page</p>} />
    </Routes>,
    { route: `/chat-groups/${id}`, user },
  )
}

function serveAll(api: MockApi, id = MASKED_GROUP_ID) {
  return serveGroup(serveUserSearch(servePermissions(api)), detailOf(id))
}

describe('ChatGroupDetailPage — states', () => {
  it('shows a skeleton, then the header, roster, messages and contact blocks', async () => {
    serveAll(mockApi())

    const { container } = renderPage(MASKED_GROUP_ID)

    expect(screen.getByRole('status', { name: 'Loading the group…' })).toBeInTheDocument()
    expect(container.querySelectorAll('.skeleton-line').length).toBeGreaterThan(0)
    const heading = await screen.findByRole('heading', { level: 1 })
    expect(heading).toHaveTextContent('Masked group')
    expect(heading).toHaveTextContent('#T41')
    expect(screen.getAllByText('Masked').length).toBeGreaterThan(0)
    expect(screen.getByRole('link', { name: 'Back to chat groups' })).toHaveAttribute('href', '/chat-groups')
    expect(screen.getByRole('list', { name: 'Members' })).toBeInTheDocument()
    expect(await screen.findByRole('list', { name: 'Group messages' })).toBeInTheDocument()
    expect(await screen.findByText('Blocked contact sharing')).toBeInTheDocument()
  })

  it("names a team group by its title", async () => {
    serveAll(mockApi(), TEAM_GROUP_ID)

    renderPage(TEAM_GROUP_ID)

    expect(await screen.findByRole('heading', { level: 1, name: 'Distribution volunteers — Mosul' })).toBeInTheDocument()
  })

  it('explains that sensitive-data access is needed, instead of a generic error', async () => {
    const api = servePermissions(mockApi()).on('get', groupUrl(MASKED_GROUP_ID), refusal(403, 'sensitive_data_required'))

    renderPage(MASKED_GROUP_ID)

    expect(await screen.findByRole('heading', { name: 'Sensitive-data access needed' })).toBeInTheDocument()
    expect(screen.getByText(/Your access level does not include sensitive data/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Try again' })).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to chat groups' })).toBeInTheDocument()
    expect(api.callsTo('get', messagesUrl(MASKED_GROUP_ID))).toHaveLength(0)
  })

  it('shows a missing group in words with the way back', async () => {
    servePermissions(mockApi()).on('get', groupUrl(99), refusal(404, 'group_not_found'))

    renderPage(99)

    expect(await screen.findByText('This chat group no longer exists. Go back to the list and refresh it.')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to chat groups' })).toBeInTheDocument()
  })

  it('recovers from a failed load through Try again', async () => {
    const user = userEvent.setup()
    const api = serveAll(mockApi()).on('get', groupUrl(MASKED_GROUP_ID), { status: 500, data: { success: false } })
    renderPage(MASKED_GROUP_ID)
    expect(await screen.findByText('A server error occurred. Please try again in a moment.')).toBeInTheDocument()

    api.on('get', groupUrl(MASKED_GROUP_ID), detailReply(detailOf(MASKED_GROUP_ID)))
    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(await screen.findByRole('list', { name: 'Members' })).toBeInTheDocument()
  })
})

describe('ChatGroupDetailPage — lifecycle', () => {
  it('offers the lifecycle controls to staff with messages:edit', async () => {
    serveAll(mockApi())

    renderPage(MASKED_GROUP_ID)

    expect(await screen.findByRole('button', { name: 'Pause' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Archive' })).toBeInTheDocument()
  })

  it('shows the state, reason and archived flag read-only without messages:edit', async () => {
    const api = servePermissions(mockApi(), matrixWith({ messages: { edit: false } }))
    serveGroup(api, detailOf(MASKED_GROUP_ID, { lifecycle: 'paused', lifecycle_reason: 'Under review', is_archived: true }))

    renderPage(MASKED_GROUP_ID, EMPLOYEE_USER)

    const header = await screen.findByRole('region', { name: 'Group state' })
    await waitFor(() => expect(within(header).getByText('Paused')).toBeInTheDocument())
    expect(within(header).getByText('Archived')).toBeInTheDocument()
    expect(within(header).getByText('Participants are being shown: Under review')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Pause' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Resume' })).not.toBeInTheDocument()
  })

  it('goes back to the list once the group has been moved to the Trash', async () => {
    const user = userEvent.setup()
    vi.mocked(askToConfirm).mockResolvedValue(true)
    const api = serveAll(mockApi())
    api.on('delete', groupUrl(MASKED_GROUP_ID), () => {
      api.on('get', groupUrl(MASKED_GROUP_ID), refusal(404, 'group_not_found'))
      return { data: { success: true } }
    })
    renderPage(MASKED_GROUP_ID)

    await user.click(await screen.findByRole('button', { name: 'Delete chat' }))

    expect(await screen.findByText('The list page')).toBeInTheDocument()
  })
})

describe('ChatGroupDetailPage — export (E3)', () => {
  it('exports every message with its masked label and role in the group', async () => {
    const user = userEvent.setup()
    vi.mocked(askForText).mockResolvedValue('1234')
    serveAll(mockApi()).on('post', '/api/admin/verify-password', { data: { ok: true } })
    renderPage(MASKED_GROUP_ID)

    await user.click(await screen.findByRole('button', { name: 'Export conversation' }))
    await user.click(screen.getByRole('menuitem', { name: 'CSV' }))

    await waitFor(() => expect(downloadCsv).toHaveBeenCalledTimes(1))
    const [filename, rows, columns] = vi.mocked(downloadCsv).mock.calls[0] as unknown as [
      string,
      Record<string, unknown>[],
      { header: string }[],
    ]
    expect(filename).toMatch(/^group_chat_41-\d{4}-\d{2}-\d{2}\.csv$/)
    expect(columns.map((c) => c.header)).toEqual(expect.arrayContaining(['masked_label', 'role_in_group']))
    expect(rows[0]).toMatchObject({ message_id: 8101, sender_name: 'Layla Hassan', masked_label: 'Donor 1', role_in_group: 'donor' })
    expect(rows[2]).toMatchObject({ sender_name: 'Rana Aziz', sender_role: 'Staff', masked_label: '' })
  })
})
