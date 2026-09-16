/**
 * MessagesPage.test.tsx — exporting the ONE donor conversation that is open.
 *
 * WHAT IT PINS
 *   - The conversation header offers "Export conversation" only when the
 *     permission matrix allows exporting the `messages` module.
 *   - After the PIN, the export makes exactly one GET of THIS thread's
 *     messages route and hands the mapped rows to the chosen download.
 *
 * WHY AN EMPLOYEE
 * lib/permissions.ts falls back to "admin tiers may export" until the matrix
 * arrives. An employee is refused by that fallback, so the button can only
 * appear because the matrix itself said yes, and can only stay hidden because
 * it said no. The refusing matrix also grants `marriage` export, so a page that
 * asked for the wrong module would show the button and fail the test.
 *
 * lib/csv and askForText are mocked for the reasons ExportCsvButton.test.tsx
 * gives.
 */
import { screen, waitFor } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import MessagesPage from './MessagesPage'
import { downloadCsv } from '../lib/csv'
import { askForText } from '../lib/dialogs'
import { DONOR_MESSAGES, DONOR_THREADS } from '../test/fixtures/legacyChats'
import { MOCK_STAFF_USER } from '../test/fixtures/session'
import { mockApi, type MockApi } from '../test/mockApi'
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
}))

// ─── Fixtures ───

const ME_URL = '/api/admin/permissions/me'
const VERIFY_URL = '/api/admin/verify-password'
const THREAD = DONOR_THREADS[0]
const MESSAGES = DONOR_MESSAGES[THREAD.id]
const MESSAGES_URL = `/api/admin/chats/${THREAD.id}/messages`
const EMPLOYEE = { ...MOCK_STAFF_USER, staff_tier: 'employee' }

/**
 * A whole page, a thread click, the menu and the PIN take about 1.5 s alone,
 * but past Vitest's 5 s default when every test file runs in parallel.
 */
const PAGE_TEST_TIMEOUT_MS = 15_000

type Matrix = Record<string, Record<string, boolean>>

// ─── Helpers ───

/** A server with the donor chat fixtures and the given permission matrix. */
function serveDonorChats(permissions: Matrix): MockApi {
  return mockApi()
    .on('get', ME_URL, { data: { success: true, tier: 'employee', permissions } })
    .on('get', '/api/admin/chats', { data: { success: true, items: DONOR_THREADS } })
    .on('get', MESSAGES_URL, { data: { status: THREAD.status, items: MESSAGES } })
    .on('get', `/api/admin/chats/${THREAD.id}/contact-blocks`, { data: { success: true, items: [] } })
    .on('post', VERIFY_URL, { data: { success: true, ok: true } })
}

/** Selects the first donor thread and waits for its messages to render. */
async function openConversation(user: UserEvent): Promise<void> {
  await user.click(await screen.findByRole('button', { name: /^Layla Hassan ↔ Sara Ali/ }))
  await screen.findByText(MESSAGES[0].body)
}

beforeEach(() => {
  vi.clearAllMocks()
})

// ─── Tests ───

describe('MessagesPage conversation export', { timeout: PAGE_TEST_TIMEOUT_MS }, () => {
  it('exports the open conversation from its own messages route after the PIN, when messages export is allowed', async () => {
    // Arrange: the download records how many requests had been made when it ran.
    const user = userEvent.setup()
    vi.mocked(askForText).mockResolvedValue('1234')
    const server = serveDonorChats({ messages: { view: true, export: true } })
    let callsAtDownload = -1
    vi.mocked(downloadCsv).mockImplementation(() => {
      callsAtDownload = server.calls.length
    })
    renderWithProviders(<MessagesPage />, { user: EMPLOYEE })
    await openConversation(user)

    // Act
    await user.click(await screen.findByRole('button', { name: 'Export conversation' }))
    await user.click(screen.getByRole('menuitem', { name: 'CSV' }))

    // Assert: one GET of this thread's messages between the PIN and the download.
    await waitFor(() => expect(downloadCsv).toHaveBeenCalledTimes(1))
    const verifiedAt = server.calls.findIndex((c) => c.method === 'post' && c.url === VERIFY_URL)
    const exportGets = server.calls
      .slice(verifiedAt, callsAtDownload)
      .filter((c) => c.method === 'get' && c.url === MESSAGES_URL)
    expect(verifiedAt).toBeGreaterThan(-1)
    expect(exportGets).toHaveLength(1)

    // Assert: the mapped rows reached the download.
    const [filename, rows] = vi.mocked(downloadCsv).mock.calls[0]
    expect(filename).toMatch(/^donor_chat_7-\d{4}-\d{2}-\d{2}\.csv$/)
    expect((rows as { message_id: number }[]).map((r) => r.message_id)).toEqual(MESSAGES.map((m) => m.id))
    expect(rows[0]).toEqual({
      message_id: 7001,
      sent_at: '2026-09-14T14:50:00.000Z',
      sender_name: 'Layla Hassan',
      sender_user_id: 101,
      sender_role: 'Grantor',
      body: 'I bought the notebooks. When can I drop them off?',
    })
  })

  it('offers no conversation export when the messages export permission is refused', async () => {
    // Arrange
    const user = userEvent.setup()
    const server = serveDonorChats({
      messages: { view: true, export: false },
      marriage: { view: true, export: true },
    })

    // Act
    renderWithProviders(<MessagesPage />, { user: EMPLOYEE })
    await openConversation(user)

    // Assert
    expect(server.callsTo('get', ME_URL).length).toBeGreaterThan(0)
    expect(screen.queryByRole('button', { name: 'Export conversation' })).not.toBeInTheDocument()
  })
})
