/**
 * StaffChatPage.test.tsx — exporting the ONE staff conversation that is open.
 *
 * WHAT IT PINS
 *   - The conversation header offers "Export conversation" only when the
 *     permission matrix allows exporting the `messages` module (decision D5).
 *   - The export REUSES the messages the page already loaded and makes no GET
 *     of the messages route of its own.
 *   - It still exports the LATEST messages: one the poll delivers while the
 *     PIN dialog is open is in the file.
 *   - A late load for the previously selected thread never puts that thread's
 *     messages in the file of the thread switched to.
 *
 * WHY REUSE MATTERS HERE
 * GET /api/admin/staff-chats/:id/messages marks the thread read for the caller
 * as a side effect (handlers/staff_chat.go Messages → staffchat.Store.MarkRead).
 * The page already makes that request when the thread is opened and every 3 s
 * after, so re-fetching for the export would only move the read marker again.
 * Reusing the loaded rows keeps the export free of any read-state change.
 *
 * TIMERS
 * The two poll tests fake setInterval and clearInterval ONLY, so each test
 * decides when the page's 3 s poll runs, while the setTimeout that
 * Testing Library's waitFor and user-event rely on stays real.
 *
 * The staff member is an employee, whose tier fallback refuses exports, so only
 * the matrix can show the button; the refusing matrix grants `marriage` export,
 * so a page gated on the wrong module fails. See MessagesPage.test.tsx for why
 * lib/csv and askForText are mocked.
 */
import { act, screen, waitFor } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import type { AxiosRequestConfig } from 'axios'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import StaffChatPage from './StaffChatPage'
import { api } from '../lib/api'
import { downloadCsv } from '../lib/csv'
import { askForText } from '../lib/dialogs'
import { STAFF_MESSAGES, STAFF_THREADS, type StaffMessage } from '../test/fixtures/legacyChats'
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
const OTHER_THREAD = STAFF_THREADS[1]
const OTHER_MESSAGES = STAFF_MESSAGES[OTHER_THREAD.id]
const OTHER_MESSAGES_URL = `/api/admin/staff-chats/${OTHER_THREAD.id}/messages`
const EMPLOYEE = { ...MOCK_STAFF_USER, staff_tier: 'employee' }

/** How often StaffChatPage reloads the open conversation. */
const POLL_INTERVAL_MS = 3000

/**
 * A whole page, a thread click, the menu and the PIN take about 1.5 s alone,
 * but past Vitest's 5 s default when every test file runs in parallel.
 */
const PAGE_TEST_TIMEOUT_MS = 15_000

/** A message the poll delivers while the operator is still typing the PIN. */
const LATE_MESSAGE: StaffMessage = {
  id: 6104,
  thread_id: THREAD.id,
  sender_user_id: 2,
  sender_name: 'Ahmed Faris',
  body: 'One more: the Basra roster is final too.',
  created_at: '2026-09-15T09:20:00Z',
}

type Matrix = Record<string, Record<string, boolean>>

const EXPORT_ALLOWED: Matrix = {
  messages: { view: true, export: true },
  marriage: { view: true, export: false },
}

// ─── Helpers ───

/** A server with the staff chat fixtures and the given permission matrix. */
function serveStaffChats(permissions: Matrix): MockApi {
  return mockApi()
    .on('get', ME_URL, { data: { success: true, tier: 'employee', permissions } })
    .on('get', '/api/admin/staff-chats', { data: { success: true, items: STAFF_THREADS } })
    .on('get', MESSAGES_URL, { data: { success: true, items: MESSAGES } })
    .on('get', OTHER_MESSAGES_URL, { data: { success: true, items: OTHER_MESSAGES } })
    .on('post', VERIFY_URL, { data: { success: true, ok: true } })
}

/** Selects the first staff thread and waits for its messages to render. */
async function openConversation(user: UserEvent): Promise<void> {
  await user.click(await screen.findByRole('button', { name: /^Ahmed Faris/ }))
  await screen.findByText(MESSAGES[0].body)
}

/** Opens the export menu of the open conversation and picks CSV. */
async function exportAsCsv(user: UserEvent): Promise<void> {
  await user.click(await screen.findByRole('button', { name: 'Export conversation' }))
  await user.click(screen.getByRole('menuitem', { name: 'CSV' }))
}

/** The message ids the (mocked) CSV download received. */
function exportedIds(): number[] {
  const [, rows] = vi.mocked(downloadCsv).mock.calls[0]
  return (rows as { message_id: number }[]).map((r) => r.message_id)
}

/**
 * Keeps the PIN dialog open until the test confirms it.
 *
 * @returns the function that types the PIN and confirms.
 */
function holdPinDialog(): (pin: string) => void {
  let confirm: (answer: string | null) => void = () => {}
  vi.mocked(askForText).mockImplementation(
    () => new Promise<string | null>((resolve) => { confirm = resolve }),
  )
  return (pin) => confirm(pin)
}

/**
 * Holds the FIRST GET of `url` until the returned function is called, then
 * answers it with what mockApi has registered; every other GET answers at
 * once. mockApi replies synchronously, so its spy is wrapped to model a slow
 * request.
 *
 * @returns the function that lets the held request land.
 */
function holdFirstLoadOf(url: string): () => void {
  const answer = vi.mocked(api.get).getMockImplementation()!
  let release: () => void = () => {}
  const released = new Promise<void>((resolve) => { release = resolve })
  let held = false
  vi.mocked(api.get).mockImplementation(((path: string, config?: AxiosRequestConfig) => {
    if (path !== url || held) return answer(path, config)
    held = true
    return released.then(() => answer(path, config))
  }) as typeof api.get)
  return () => release()
}

/** Runs the page's conversation poll once. */
async function runPoll(): Promise<void> {
  await act(async () => {
    vi.advanceTimersByTime(POLL_INTERVAL_MS)
  })
}

// Reset, not just clear: tests replace askForText's and downloadCsv's
// implementations, and a leftover one would answer the next test.
beforeEach(() => {
  vi.resetAllMocks()
})

afterEach(() => {
  vi.useRealTimers()
})

// ─── Tests ───

describe('StaffChatPage conversation export', { timeout: PAGE_TEST_TIMEOUT_MS }, () => {
  it('exports the loaded conversation after the PIN without fetching its messages again, when messages export is allowed', async () => {
    // Arrange: the download records how many requests had been made when it ran.
    const user = userEvent.setup()
    vi.mocked(askForText).mockResolvedValue('1234')
    const server = serveStaffChats(EXPORT_ALLOWED)
    let callsAtDownload = -1
    vi.mocked(downloadCsv).mockImplementation(() => {
      callsAtDownload = server.calls.length
    })
    renderWithProviders(<StaffChatPage />, { user: EMPLOYEE })
    await openConversation(user)

    // Act
    await exportAsCsv(user)

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

  it('includes a message the poll delivers while the PIN dialog is still open', async () => {
    // Arrange: the operator starts the export, and the PIN dialog stays open.
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] })
    const user = userEvent.setup()
    const confirmPin = holdPinDialog()
    const server = serveStaffChats(EXPORT_ALLOWED)
    renderWithProviders(<StaffChatPage />, { user: EMPLOYEE })
    await openConversation(user)
    await exportAsCsv(user)
    await waitFor(() => expect(askForText).toHaveBeenCalledTimes(1))

    // Act: the poll brings a new message, then the operator confirms the PIN.
    server.on('get', MESSAGES_URL, { data: { success: true, items: [...MESSAGES, LATE_MESSAGE] } })
    await runPoll()
    expect(await screen.findByText(LATE_MESSAGE.body)).toBeInTheDocument()
    await act(async () => confirmPin('1234'))

    // Assert
    await waitFor(() => expect(downloadCsv).toHaveBeenCalledTimes(1))
    expect(exportedIds()).toEqual([...MESSAGES, LATE_MESSAGE].map((m) => m.id))
  })

  it("never puts the previous thread's messages in the export of the thread switched to", async () => {
    // Arrange: thread 61's first load is slow.
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] })
    const user = userEvent.setup()
    vi.mocked(askForText).mockResolvedValue('1234')
    serveStaffChats(EXPORT_ALLOWED)
    const releaseFirstLoad = holdFirstLoadOf(MESSAGES_URL)
    renderWithProviders(<StaffChatPage />, { user: EMPLOYEE })

    // Act: open 61, switch to 62 before 61 loads; 62 loads and can be exported.
    await user.click(await screen.findByRole('button', { name: /^Ahmed Faris/ }))
    await user.click(screen.getByRole('button', { name: /^Zainab Kadhim/ }))
    expect(await screen.findByRole('button', { name: 'Export conversation' })).toBeInTheDocument()

    // Act: 61's slow load lands now and replaces the list while 62 is open.
    await act(async () => releaseFirstLoad())
    expect(await screen.findByText(MESSAGES[0].body)).toBeInTheDocument()

    // Assert: nothing is offered while the list holds only another thread's rows.
    expect(screen.queryByRole('button', { name: 'Export conversation' })).not.toBeInTheDocument()

    // Act: the next poll reloads 62, and the operator exports it.
    await runPoll()
    await waitFor(() => expect(screen.queryByText(MESSAGES[0].body)).not.toBeInTheDocument())
    await exportAsCsv(user)

    // Assert: the file is thread 62's, and holds thread 62's messages only.
    await waitFor(() => expect(downloadCsv).toHaveBeenCalledTimes(1))
    const [filename] = vi.mocked(downloadCsv).mock.calls[0]
    expect(filename).toMatch(/^staff_chat_62-\d{4}-\d{2}-\d{2}\.csv$/)
    expect(exportedIds()).toEqual(OTHER_MESSAGES.map((m) => m.id))
  })
})
