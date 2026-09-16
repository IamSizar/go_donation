/**
 * MarriageChatsPage.test.tsx — exporting the ONE marriage conversation that is open.
 *
 * WHAT IT PINS
 *   - The conversation header offers "Export conversation" only when the
 *     permission matrix allows exporting the `marriage` module, the same module
 *     that gates the marriage messages route (perm("marriage", "view")).
 *   - After the PIN, the export makes exactly one GET of THIS thread's
 *     messages route and hands the mapped rows to the chosen download.
 *
 * The staff member is an employee, whose tier fallback refuses exports, so only
 * the matrix can show the button. Each matrix grants the OTHER chat module the
 * opposite answer, so a page gated on `messages` by mistake fails both tests.
 * See MessagesPage.test.tsx for why lib/csv and askForText are mocked.
 */
import { screen, waitFor } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import MarriageChatsPage from './MarriageChatsPage'
import { downloadCsv } from '../lib/csv'
import { askForText } from '../lib/dialogs'
import { MARRIAGE_MESSAGES, MARRIAGE_THREADS } from '../test/fixtures/legacyChats'
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
const THREAD = MARRIAGE_THREADS[0]
const MESSAGES = MARRIAGE_MESSAGES[THREAD.id]
const MESSAGES_URL = `/api/admin/marriage/chats/${THREAD.id}/messages`
const EMPLOYEE = { ...MOCK_STAFF_USER, staff_tier: 'employee' }

/**
 * A whole page, a thread click, the menu and the PIN take about 1.5 s alone,
 * but past Vitest's 5 s default when every test file runs in parallel.
 */
const PAGE_TEST_TIMEOUT_MS = 15_000

type Matrix = Record<string, Record<string, boolean>>

// ─── Helpers ───

/** A server with the marriage chat fixtures and the given permission matrix. */
function serveMarriageChats(permissions: Matrix): MockApi {
  return mockApi()
    .on('get', ME_URL, { data: { success: true, tier: 'employee', permissions } })
    .on('get', '/api/admin/marriage/chats', { data: { success: true, items: MARRIAGE_THREADS } })
    .on('get', MESSAGES_URL, { data: { status: THREAD.status, items: MESSAGES } })
    .on('post', VERIFY_URL, { data: { success: true, ok: true } })
}

/** Selects the first marriage thread and waits for its messages to render. */
async function openConversation(user: UserEvent): Promise<void> {
  await user.click(await screen.findByRole('button', { name: /^Karim Adel ↔ Huda Salim/ }))
  await screen.findByText(MESSAGES[0].body)
}

beforeEach(() => {
  vi.clearAllMocks()
})

// ─── Tests ───

describe('MarriageChatsPage conversation export', { timeout: PAGE_TEST_TIMEOUT_MS }, () => {
  it('exports the open conversation from its own messages route after the PIN, when marriage export is allowed', async () => {
    // Arrange: the download records how many requests had been made when it ran.
    const user = userEvent.setup()
    vi.mocked(askForText).mockResolvedValue('1234')
    const server = serveMarriageChats({
      marriage: { view: true, export: true },
      messages: { view: true, export: false },
    })
    let callsAtDownload = -1
    vi.mocked(downloadCsv).mockImplementation(() => {
      callsAtDownload = server.calls.length
    })
    renderWithProviders(<MarriageChatsPage />, { user: EMPLOYEE })
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

    // Assert: the mapped rows reached the download, staff named as Support.
    const [filename, rows] = vi.mocked(downloadCsv).mock.calls[0]
    const exported = rows as { message_id: number; sender_role: string }[]
    expect(filename).toMatch(/^marriage_chat_51-\d{4}-\d{2}-\d{2}\.csv$/)
    expect(exported.map((r) => r.message_id)).toEqual(MESSAGES.map((m) => m.id))
    expect(exported[0]).toEqual({
      message_id: 5101,
      sent_at: '2026-09-12T09:00:00.000Z',
      sender_name: 'Karim Adel',
      sender_user_id: 108,
      sender_role: 'Requester',
      body: 'I would like to arrange a family meeting.',
    })
    expect(exported.find((r) => r.message_id === 5103)?.sender_role).toBe('Support')
  })

  it('offers no conversation export when the marriage export permission is refused', async () => {
    // Arrange
    const user = userEvent.setup()
    const server = serveMarriageChats({
      marriage: { view: true, export: false },
      messages: { view: true, export: true },
    })

    // Act
    renderWithProviders(<MarriageChatsPage />, { user: EMPLOYEE })
    await openConversation(user)

    // Assert
    expect(server.callsTo('get', ME_URL).length).toBeGreaterThan(0)
    expect(screen.queryByRole('button', { name: 'Export conversation' })).not.toBeInTheDocument()
  })
})
