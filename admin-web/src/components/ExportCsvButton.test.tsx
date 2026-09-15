/**
 * ExportCsvButton.test.tsx — the PIN-gated export menu, in each of its modes.
 *
 * WHAT IT PINS
 *   - rows mode (every list page today) still downloads the rows it was given.
 *   - Failures name what actually failed. A verify-password request that fails
 *     (403 "no password is set", a 500, no network) is reported as that
 *     failure, in rows mode and in the legacy onExport mode alike. Only a PIN
 *     the server refused is reported as a wrong password.
 *
 * WHAT IS MOCKED
 *   - lib/csv's download functions: jsdom has no URL.createObjectURL and no
 *     window.open, and what matters here is which rows reach them.
 *   - lib/dialogs' askForText: the PIN dialog itself is AskDialog's concern;
 *     this file only needs its two outcomes, a typed PIN or null for cancel.
 *   - `api`, through mockApi: permissions/me and verify-password.
 *
 * Strings are asserted as literal English on purpose, as in
 * ContactBlocksPanel.test.tsx: a missing key would otherwise pass unnoticed.
 */
import { screen, waitFor } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import ExportCsvButton from './ExportCsvButton'
import { downloadWord, type CsvColumn } from '../lib/csv'
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
