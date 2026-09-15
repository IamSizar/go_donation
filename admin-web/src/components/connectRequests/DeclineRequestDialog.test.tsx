/**
 * DeclineRequestDialog.test.tsx — declining a connect request with a reason
 * the member will read (Phase 6c, OPOS #26400).
 *
 * Pins: the operator is told the member sees the reason; Decline is disabled
 * while the reason is blank; a touched blank reason names the rule; the body
 * sends the trimmed reason; 409 connect_request_decided and the uncoded 404
 * are translated and keep the dialog open.
 */
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import DeclineRequestDialog from './DeclineRequestDialog'
import { servePermissions } from '../../test/chatGroupsKit'
import { CONNECT_REQUESTS } from '../../test/fixtures/chatGroups'
import { mockApi } from '../../test/mockApi'
import { renderWithProviders } from '../../test/render'

const REQUEST = CONNECT_REQUESTS[0]
const DECLINE_URL = `/api/admin/chat-groups/connect-requests/${REQUEST.id}/decline`

function renderDialog() {
  const onClose = vi.fn()
  const onDeclined = vi.fn()
  renderWithProviders(<DeclineRequestDialog request={REQUEST} onClose={onClose} onDeclined={onDeclined} />)
  return { onClose, onDeclined }
}

const reasonBox = () => screen.getByRole('textbox', { name: 'Reason' })
const declineButton = () => screen.getByRole('button', { name: 'Decline request' })

describe('DeclineRequestDialog', () => {
  it('tells the operator the member will see the reason, and gates on a non-blank one', async () => {
    const user = userEvent.setup()
    servePermissions(mockApi())
    renderDialog()

    expect(screen.getByText(/The member sees this reason in the app/)).toBeInTheDocument()
    expect(declineButton()).toBeDisabled()
    await user.type(reasonBox(), '   ')
    await user.tab()

    expect(screen.getByText('Enter a reason for the member.')).toBeInTheDocument()
    expect(declineButton()).toBeDisabled()
  })

  it('sends the trimmed reason and reports success', async () => {
    const user = userEvent.setup()
    const api = servePermissions(mockApi()).on('post', DECLINE_URL, { data: { success: true } })
    const { onDeclined } = renderDialog()

    await user.type(reasonBox(), '  We cannot arrange this one.  ')
    await user.click(declineButton())

    await waitFor(() => expect(onDeclined).toHaveBeenCalled())
    expect(api.callsTo('post', DECLINE_URL).map((c) => c.data)).toEqual([{ reason: 'We cannot arrange this one.' }])
    expect(await screen.findByText('Request declined')).toBeInTheDocument()
  })

  it('translates an already-decided refusal and keeps the dialog open', async () => {
    const user = userEvent.setup()
    servePermissions(mockApi()).on('post', DECLINE_URL, {
      status: 409,
      data: { success: false, error: 'This request has already been decided.', code: 'connect_request_decided' },
    })
    const { onDeclined } = renderDialog()

    await user.type(reasonBox(), 'No')
    await user.click(declineButton())

    expect(await screen.findByRole('alert')).toHaveTextContent('Another staff member has already decided this request.')
    expect(onDeclined).not.toHaveBeenCalled()
  })

  it('translates the uncoded not-found refusal', async () => {
    const user = userEvent.setup()
    servePermissions(mockApi()).on('post', DECLINE_URL, {
      status: 404,
      data: { success: false, error: 'Connect request not found.' },
    })
    renderDialog()

    await user.type(reasonBox(), 'No')
    await user.click(declineButton())

    expect(await screen.findByRole('alert')).toHaveTextContent('This connect request no longer exists.')
  })
})
