/**
 * ExportCsvButton.test.tsx — the PIN-gated export menu, in each of its modes.
 *
 * WHAT IT PINS
 *   - loadRows mode (the per-conversation export): the rows are loaded only
 *     AFTER the PIN step-up succeeds, exactly once, and handed to the download
 *     the operator picked. Cancelling the PIN loads nothing.
 *   - rows mode (every list page today) still downloads the rows it was given.
 *   - Failures name what actually failed. A load that fails is reported as a
 *     failed load; a verify-password request that fails (403 "no password is
 *     set", a 500, no network) is reported as that failure, in rows mode and in
 *     the legacy onExport mode alike. Only a PIN the server refused is reported
 *     as a wrong password.
 *
 * WHAT IS MOCKED
 *   - lib/csv's download functions: jsdom has no URL.createObjectURL and no
 *     window.open, and what matters here is which rows reach them.
 *   - lib/dialogs' askForText: the PIN dialog itself is AskDialog's concern;
 *     this file only needs its two outcomes, a typed PIN or null for cancel.
 *   - `api`, through mockApi: permissions/me, verify-password and, for the
 *     failed-load case, a messages route answering 500.
 *
 * Strings are asserted as literal English on purpose, as in
 * ContactBlocksPanel.test.tsx: a missing key would otherwise pass unnoticed.
 */
import { screen, waitFor } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import ExportCsvButton from './ExportCsvButton'
import { api } from '../lib/api'
import { downloadCsv, downloadExcel, downloadWord, type CsvColumn } from '../lib/csv'
import { askForText } from '../lib/dialogs'
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
const CONVERSATION_URL = '/api/admin/chats/7/messages'

type Row = { id: number; body: string }

const ROWS: Row[] = [
  { id: 1, body: 'Hello, world' },
  { id: 2, body: 'Line one\nLine two' },
]

const COLUMNS: CsvColumn<Row>[] = [
  { header: 'id', get: (r) => r.id },
  { header: 'body', get: (r) => r.body },
]

const PIN_ACCEPTED = { data: { success: true, ok: true } }

/** The 403 admin_status.go VerifyPassword sends when the account has no password. */
const NO_PASSWORD_SET = {
  status: 403,
  data: { success: false, ok: false, error: 'No password is set on your account; ask a Super-Admin to set one.' },
}

// ─── Helpers ───

/** A server whose permission matrix lets the signed-in staff member export messages. */
function serverAllowingExport(): MockApi {
  return mockApi().on('get', ME_URL, {
    data: { success: true, tier: 'super_admin', permissions: { messages: { view: true, export: true } } },
  })
}

/** Opens the export menu by its button name and picks one format. */
async function chooseFormat(user: UserEvent, format: string, buttonName = 'Export'): Promise<void> {
  await user.click(await screen.findByRole('button', { name: buttonName }))
  await user.click(screen.getByRole('menuitem', { name: format }))
}

// vi.fn() mocks keep their call history across tests (restoreMocks only
// undoes vi.spyOn), so every test starts from a clean count.
beforeEach(() => {
  vi.clearAllMocks()
})

// ─── loadRows mode ───

describe('ExportCsvButton with loadRows', () => {
  it('never loads the rows when the operator cancels the PIN', async () => {
    // Arrange
    const user = userEvent.setup()
    const server = serverAllowingExport()
    vi.mocked(askForText).mockResolvedValue(null)
    const loadRows = vi.fn(async () => ROWS)
    renderWithProviders(
      <ExportCsvButton loadRows={loadRows} columns={COLUMNS} filenameBase="conversation" module="messages" />,
    )

    // Act
    await chooseFormat(user, 'CSV')

    // Assert
    await waitFor(() => expect(screen.getByRole('button', { name: 'Export' })).toBeEnabled())
    expect(askForText).toHaveBeenCalledTimes(1)
    expect(loadRows).not.toHaveBeenCalled()
    expect(downloadCsv).not.toHaveBeenCalled()
    expect(server.callsTo('post', VERIFY_URL)).toHaveLength(0)
  })

  it('loads the rows exactly once after a confirmed PIN, then downloads those rows', async () => {
    // Arrange: the loader records whether the PIN had been verified when it ran.
    const user = userEvent.setup()
    const server = serverAllowingExport().on('post', VERIFY_URL, PIN_ACCEPTED)
    vi.mocked(askForText).mockResolvedValue('1234')
    let verifiedBeforeLoad = false
    const loadRows = vi.fn(async () => {
      verifiedBeforeLoad = server.callsTo('post', VERIFY_URL).length === 1
      return ROWS
    })
    renderWithProviders(
      <ExportCsvButton
        loadRows={loadRows}
        columns={COLUMNS}
        filenameBase="conversation"
        title="Conversation #7"
        module="messages"
        label="Export conversation"
      />,
    )

    // Act
    await chooseFormat(user, 'Excel', 'Export conversation')

    // Assert
    await waitFor(() => expect(downloadExcel).toHaveBeenCalledTimes(1))
    expect(loadRows).toHaveBeenCalledTimes(1)
    expect(verifiedBeforeLoad).toBe(true)
    expect(server.callsTo('post', VERIFY_URL)).toEqual([
      { method: 'post', url: VERIFY_URL, data: { password: '1234' } },
    ])
    expect(downloadExcel).toHaveBeenCalledWith(
      expect.stringMatching(/^conversation-\d{4}-\d{2}-\d{2}\.xls$/),
      ROWS,
      COLUMNS,
    )
  })

  it('reports a failed load as a failed load, not as a wrong password', async () => {
    // Arrange: the PIN is fine; the conversation route answers 500 with the
    // backend's English prose, which describeError() must not show.
    const user = userEvent.setup()
    serverAllowingExport()
      .on('post', VERIFY_URL, PIN_ACCEPTED)
      .on('get', CONVERSATION_URL, { status: 500, data: { success: false, error: 'Database error.' } })
    vi.mocked(askForText).mockResolvedValue('1234')
    const loadRows = () => api.get<Row[]>(CONVERSATION_URL).then((res) => res.data)
    renderWithProviders(
      <ExportCsvButton loadRows={loadRows} columns={COLUMNS} filenameBase="conversation" module="messages" />,
    )

    // Act
    await chooseFormat(user, 'CSV')

    // Assert
    expect(
      await screen.findByText(
        "Couldn't load the data to export. A server error occurred. Please try again in a moment.",
      ),
    ).toBeInTheDocument()
    expect(screen.queryByText('Incorrect password — cancelled.')).not.toBeInTheDocument()
    expect(screen.queryByText('Database error.')).not.toBeInTheDocument()
    expect(downloadCsv).not.toHaveBeenCalled()
  })

  it('still reports a refused PIN as a wrong password, and loads nothing', async () => {
    // Arrange: verify-password refuses the PIN with 200 { ok: false }, which is
    // what admin_status.go VerifyPassword sends for a wrong password.
    const user = userEvent.setup()
    serverAllowingExport().on('post', VERIFY_URL, {
      data: { success: true, ok: false, error: 'Incorrect password.' },
    })
    vi.mocked(askForText).mockResolvedValue('wrong')
    const loadRows = vi.fn(async () => ROWS)
    renderWithProviders(
      <ExportCsvButton loadRows={loadRows} columns={COLUMNS} filenameBase="conversation" module="messages" />,
    )

    // Act
    await chooseFormat(user, 'CSV')

    // Assert
    expect(await screen.findByText('Incorrect password.')).toBeInTheDocument()
    expect(loadRows).not.toHaveBeenCalled()
    expect(downloadCsv).not.toHaveBeenCalled()
  })

  it('reports a download that throws with the generic line, and with nothing else', async () => {
    // Arrange: the PIN is accepted and the rows load, but building the file
    // throws. Once, so the throw cannot reach another test.
    const user = userEvent.setup()
    serverAllowingExport().on('post', VERIFY_URL, PIN_ACCEPTED)
    vi.mocked(askForText).mockResolvedValue('1234')
    vi.mocked(downloadCsv).mockImplementationOnce(() => {
      throw new Error('Blob construction failed')
    })
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})
    renderWithProviders(
      <ExportCsvButton loadRows={async () => ROWS} columns={COLUMNS} filenameBase="conversation" module="messages" />,
    )

    // Act
    await chooseFormat(user, 'CSV')

    // Assert: one toast, the generic line; the detail goes to the console.
    expect(await screen.findByText('Something went wrong. Please try again.')).toBeInTheDocument()
    expect(screen.getAllByRole('status')).toHaveLength(1)
    expect(consoleError).toHaveBeenCalledWith('ExportCsvButton: building the export file failed', expect.any(Error))
  })
})

// ─── rows mode ───

describe('ExportCsvButton with rows', () => {
  it('keeps downloading the rows it was given when no loader is passed', async () => {
    // Arrange
    const user = userEvent.setup()
    serverAllowingExport().on('post', VERIFY_URL, PIN_ACCEPTED)
    vi.mocked(askForText).mockResolvedValue('1234')
    renderWithProviders(
      <ExportCsvButton rows={ROWS} columns={COLUMNS} filenameBase="messages" title="Messages" module="messages" />,
    )

    // Act
    await chooseFormat(user, 'Word')

    // Assert
    await waitFor(() => expect(downloadWord).toHaveBeenCalledTimes(1))
    expect(downloadWord).toHaveBeenCalledWith(
      expect.stringMatching(/^messages-\d{4}-\d{2}-\d{2}\.doc$/),
      'Messages',
      ROWS,
      COLUMNS,
    )
  })

  it('reports a verify-password request that fails as that failure, not as a wrong password', async () => {
    // Arrange
    const user = userEvent.setup()
    serverAllowingExport().on('post', VERIFY_URL, NO_PASSWORD_SET)
    vi.mocked(askForText).mockResolvedValue('1234')
    renderWithProviders(
      <ExportCsvButton rows={ROWS} columns={COLUMNS} filenameBase="messages" module="messages" />,
    )

    // Act
    await chooseFormat(user, 'Word')

    // Assert
    expect(
      await screen.findByText('No password is set on your account; ask a Super-Admin to set one.'),
    ).toBeInTheDocument()
    expect(screen.queryByText('Incorrect password — cancelled.')).not.toBeInTheDocument()
    expect(downloadWord).not.toHaveBeenCalled()
  })
})

// ─── legacy onExport mode ───

describe('ExportCsvButton with onExport', () => {
  it('reports a verify-password request that fails as that failure, not as a wrong password', async () => {
    // Arrange: the server breaks; describeError() shows its translated line,
    // never the backend's English prose.
    const user = userEvent.setup()
    serverAllowingExport().on('post', VERIFY_URL, {
      status: 500,
      data: { success: false, error: 'Database error.' },
    })
    vi.mocked(askForText).mockResolvedValue('1234')
    const onExport = vi.fn()
    renderWithProviders(<ExportCsvButton onExport={onExport} />)

    // Act
    await user.click(await screen.findByRole('button', { name: 'Export CSV' }))

    // Assert
    expect(
      await screen.findByText('A server error occurred. Please try again in a moment.'),
    ).toBeInTheDocument()
    expect(screen.queryByText('Incorrect password — cancelled.')).not.toBeInTheDocument()
    expect(onExport).not.toHaveBeenCalled()
  })
})
