/**
 * StaffChatPage.test.tsx — exporting the ONE staff conversation that is open.
 *
 * WHAT IT PINS
 *   - The conversation header offers "Export conversation" only when the
 *     permission matrix allows exporting the `messages` module (decision D5).
 *   - The export REUSES the messages the page already loaded and makes no GET
 *     of the messages route of its own.
 *
 * WHY REUSE MATTERS HERE
 * GET /api/admin/staff-chats/:id/messages marks the thread read for the caller
 * as a side effect (handlers/staff_chat.go Messages → staffchat.Store.MarkRead).
 * The page already makes that request when the thread is opened and every 3 s
 * after, so re-fetching for the export would only move the read marker again.
 * Reusing the loaded rows keeps the export free of any read-state change.
 *
 * The staff member is an employee, whose tier fallback refuses exports, so only
 * the matrix can show the button; the refusing matrix grants `marriage` export,
 * so a page gated on the wrong module fails. See MessagesPage.test.tsx for why
 * lib/csv and askForText are mocked.
 */
import { screen, waitFor } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import StaffChatPage from './StaffChatPage'
import { downloadCsv } from '../lib/csv'
import { askForText } from '../lib/dialogs'
import { STAFF_MESSAGES, STAFF_THREADS } from '../test/fixtures/legacyChats'
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
const THREAD = STAFF_THREADS[0]
const MESSAGES = STAFF_MESSAGES[THREAD.id]
const MESSAGES_URL = `/api/admin/staff-chats/${THREAD.id}/messages`
const EMPLOYEE = { ...MOCK_STAFF_USER, staff_tier: 'employee' }

/**
 * A whole page, a thread click, the menu and the PIN take about 1.5 s alone,
 * but past Vitest's 5 s default when every test file runs in parallel.
 */
const PAGE_TEST_TIMEOUT_MS = 15_000

type Matrix = Record<string, Record<string, boolean>>

// ─── Helpers ───

/** A server with the staff chat fixtures and the given permission matrix. */
function serveStaffChats(permissions: Matrix): MockApi {
  return mockApi()
    .on('get', ME_URL, { data: { success: true, tier: 'employee', permissions } })
    .on('get', '/api/admin/staff-chats', { data: { success: true, items: STAFF_THREADS } })
    .on('get', MESSAGES_URL, { data: { success: true, items: MESSAGES } })
    .on('post', VERIFY_URL, { data: { success: true, ok: true } })
}

/** Selects the first staff thread and waits for its messages to render. */
async function openConversation(user: UserEvent): Promise<void> {
  await user.click(await screen.findByRole('button', { name: /^Ahmed Faris/ }))
  await screen.findByText(MESSAGES[0].body)
}

beforeEach(() => {
  vi.clearAllMocks()
})

// ─── Tests ───

describe('StaffChatPage conversation export', { timeout: PAGE_TEST_TIMEOUT_MS }, () => {
  it('exports the loaded conversation after the PIN without fetching its messages again, when messages export is allowed', async () => {
    // Arrange: the download records how many requests had been made when it ran.
    const user = userEvent.setup()
    vi.mocked(askForText).mockResolvedValue('1234')
    const server = serveStaffChats({
      messages: { view: true, export: true },
      marriage: { view: true, export: false },
    })
    let callsAtDownload = -1
    vi.mocked(downloadCsv).mockImplementation(() => {
      callsAtDownload = server.calls.length
    })
    renderWithProviders(<StaffChatPage />, { user: EMPLOYEE })
    await openConversation(user)

    // Act
    await user.click(await screen.findByRole('button', { name: 'Export conversation' }))
    await user.click(screen.getByRole('menuitem', { name: 'CSV' }))

    // Assert: no GET of the messages route between the PIN and the download,
    // so the export moved no read marker.
    await waitFor(() => expect(downloadCsv).toHaveBeenCalledTimes(1))
    const verifiedAt = server.calls.findIndex((c) => c.method === 'post' && c.url === VERIFY_URL)
    const exportGets = server.calls
      .slice(verifiedAt, callsAtDownload)
      .filter((c) => c.method === 'get' && c.url === MESSAGES_URL)
    expect(verifiedAt).toBeGreaterThan(-1)
    expect(exportGets).toHaveLength(0)

    // Assert: the loaded rows, mapped, reached the download. Staff member 1 is
    // the signed-in employee; staff member 2 is the thread's admin.
    const [filename, rows] = vi.mocked(downloadCsv).mock.calls[0]
    const exported = rows as { message_id: number; sender_role: string }[]
    expect(filename).toMatch(/^staff_chat_61-\d{4}-\d{2}-\d{2}\.csv$/)
    expect(exported.map((r) => r.message_id)).toEqual(MESSAGES.map((m) => m.id))
    expect(exported[0]).toEqual({
      message_id: 6101,
      sent_at: '2026-09-15T08:30:00.000Z',
      sender_name: 'Rana Aziz',
      sender_user_id: 1,
      sender_role: 'Employee',
      body: 'Morning. The Mosul distribution group is set up.',
    })
    expect(exported.find((r) => r.message_id === 6102)?.sender_role).toBe('Admin')
  })

  it('offers no conversation export when the messages export permission is refused', async () => {
    // Arrange
    const user = userEvent.setup()
    const server = serveStaffChats({
      messages: { view: true, export: false },
      marriage: { view: true, export: true },
    })

    // Act
    renderWithProviders(<StaffChatPage />, { user: EMPLOYEE })
    await openConversation(user)

    // Assert
    expect(server.callsTo('get', ME_URL).length).toBeGreaterThan(0)
    expect(screen.queryByRole('button', { name: 'Export conversation' })).not.toBeInTheDocument()
  })
})
