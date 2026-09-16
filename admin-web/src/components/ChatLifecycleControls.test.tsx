/**
 * ChatLifecycleControls.test.tsx — the Delete gate and its confirmation copy
 * (OPOS #26492).
 *
 * WHAT IT PINS
 *   - Delete is offered only with the delete permission of the module whose
 *     route the server guards it with (messages:delete or marriage:delete in
 *     backend/cmd/server/main.go). Edit alone is not enough.
 *   - The confirmation says an administrator can restore the chat: Trash
 *     restore is RequireAdminTier (admin or super_admin), not Super-Admin only.
 *     Permanent deletion (purge) stays RequireSuperAdmin, and the copy says so.
 *
 * WHAT IS MOCKED
 *   - lib/dialogs' askToConfirm, so the test reads the message it was given.
 *   - `api`, through mockApi: only the permission matrix.
 *
 * The session is an `employee`, whose tier fallback denies, so a hidden
 * button cannot pass just because the matrix had not loaded yet.
 */
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import ChatLifecycleControls from './ChatLifecycleControls'
import { askToConfirm } from '../lib/dialogs'
import { EMPLOYEE_USER, matrixWith, servePermissions } from '../test/chatGroupsKit'
import { mockApi } from '../test/mockApi'
import { renderWithProviders } from '../test/render'

vi.mock('../lib/dialogs', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/dialogs')>()),
  askToConfirm: vi.fn(),
}))

const THREAD = { id: 12, lifecycle: 'open' as const }

/** Renders the strip for a marriage chat, whose delete route needs marriage:delete. */
function renderStrip() {
  renderWithProviders(
    <ChatLifecycleControls basePath="/api/admin/marriage/chats/12" deleteModule="marriage" thread={THREAD} onChanged={vi.fn()} />,
    { user: EMPLOYEE_USER },
  )
}

describe('ChatLifecycleControls — Delete', () => {
  it('hides Delete from staff who can edit but not delete in that module', async () => {
    servePermissions(mockApi(), matrixWith({ marriage: { edit: true, delete: false }, messages: { delete: true } }))

    renderStrip()

    expect(await screen.findByRole('button', { name: 'Archive' })).toBeInTheDocument()
    // Let the matrix land before asserting absence.
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Delete chat' })).not.toBeInTheDocument())
    await new Promise((r) => setTimeout(r, 0))
    expect(screen.queryByRole('button', { name: 'Delete chat' })).not.toBeInTheDocument()
  })

  it('offers Delete with that module’s delete permission, and says an administrator can restore it', async () => {
    const user = userEvent.setup()
    vi.mocked(askToConfirm).mockResolvedValue(false)
    servePermissions(mockApi(), matrixWith({ marriage: { delete: true } }))

    renderStrip()
    await user.click(await screen.findByRole('button', { name: 'Delete chat' }))

    const message = vi.mocked(askToConfirm).mock.calls[0][0].message
    expect(message).toContain('An administrator can restore it')
    expect(message).not.toContain('A Super-Admin can restore')
  })
})
