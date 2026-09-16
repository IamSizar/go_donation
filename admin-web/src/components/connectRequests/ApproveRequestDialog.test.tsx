/**
 * ApproveRequestDialog.test.tsx — approving a connect request by opening its
 * group (Phase 6c, OPOS #26400).
 *
 * Pins, through the real dialog, 6a's KindCards and MemberRowsEditor, the real
 * i18n strings and a mocked `api`:
 *   - the requester is pre-filled as member 1, and the exact approve body
 *     (CreateGroupBody: kind, member_title, members[{user_id, role_in_group, label}]);
 *   - Approve stays disabled while a rule is broken, including a team without
 *     a title (D7) and a draft whose requester was removed;
 *   - refusals are translated and placed: 409 connect_request_decided atop the
 *     form, 409 group_label_conflict beside the members;
 *   - without users:view, the D2 guidance card replaces the member rows.
 */
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import ApproveRequestDialog from './ApproveRequestDialog'
import { chooseRole, matrixWith, memberRow, servePermissions, serveUserSearch } from '../../test/chatGroupsKit'
import { CONNECT_REQUESTS } from '../../test/fixtures/chatGroups'
import { mockApi, type MockApi } from '../../test/mockApi'
import { renderWithProviders } from '../../test/render'

const REQUEST = { ...CONNECT_REQUESTS[1], requester_name: 'Sara Ali' }
const APPROVE_URL = `/api/admin/chat-groups/connect-requests/${REQUEST.id}/approve`

function readyApi(): MockApi {
  return serveUserSearch(servePermissions(mockApi()))
}

function renderDialog(request = REQUEST) {
  const onClose = vi.fn()
  const onApproved = vi.fn()
  renderWithProviders(<ApproveRequestDialog request={request} onClose={onClose} onApproved={onApproved} />)
  return { onClose, onApproved }
}

const approveButton = () => screen.getByRole('button', { name: 'Approve and open group' })

describe('ApproveRequestDialog', () => {
  it('pre-fills the requester and sends the approve body the backend binds', async () => {
    const user = userEvent.setup()
    const api = readyApi().on('post', APPROVE_URL, { data: { success: true, group_id: 100010 } })
    const { onApproved } = renderDialog()

    expect(memberRow(1)).toHaveTextContent('Sara Ali')
    await user.click(screen.getByRole('radio', { name: /Masked group/ }))
    await chooseRole(user, 1, 'donor')
    await user.click(approveButton())

    await waitFor(() => expect(onApproved).toHaveBeenCalledWith(100010))
    expect(api.callsTo('post', APPROVE_URL).map((c) => c.data)).toEqual([
      { kind: 'masked', member_title: '', members: [{ user_id: 102, role_in_group: 'donor', label: '' }] },
    ])
    expect(await screen.findByText('Request approved. The group is open.')).toBeInTheDocument()
  })

  it('keeps Approve disabled for a team group until it has a name', async () => {
    const user = userEvent.setup()
    readyApi()
    renderDialog()

    await user.click(screen.getByRole('radio', { name: /Team group/ }))
    await chooseRole(user, 1, 'volunteer')
    expect(approveButton()).toBeDisabled()
    await user.type(screen.getByRole('textbox', { name: 'Team name' }), 'Delivery team')

    expect(approveButton()).toBeEnabled()
  })

  it('refuses to send a group without the requester, and says why', async () => {
    const user = userEvent.setup()
    readyApi()
    renderDialog()
    await user.click(screen.getByRole('radio', { name: /Masked group/ }))

    await user.click(screen.getByRole('button', { name: 'Remove member 1' }))

    expect(screen.getByText('The person who sent the request must be a member of the group.')).toBeInTheDocument()
    expect(approveButton()).toBeDisabled()
  })

  it('shows an already-decided refusal atop the form and keeps the dialog open', async () => {
    const user = userEvent.setup()
    readyApi().on('post', APPROVE_URL, {
      status: 409,
      data: { success: false, error: 'This request has already been decided.', code: 'connect_request_decided' },
    })
    const { onApproved } = renderDialog()
    await user.click(screen.getByRole('radio', { name: /Masked group/ }))
    await chooseRole(user, 1, 'donor')

    await user.click(approveButton())

    expect(await screen.findByRole('alert')).toHaveTextContent('Another staff member has already decided this request.')
    expect(onApproved).not.toHaveBeenCalled()
  })

  it('shows a label conflict beside the members', async () => {
    const user = userEvent.setup()
    readyApi().on('post', APPROVE_URL, {
      status: 409,
      data: { success: false, error: 'Label taken.', code: 'group_label_conflict' },
    })
    renderDialog()
    await user.click(screen.getByRole('radio', { name: /Masked group/ }))
    await chooseRole(user, 1, 'donor')

    await user.click(approveButton())

    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('Another member of this group already has this label.')
    expect(alert.closest('fieldset')).not.toBeNull()
  })

  it('shows the user-search guidance to staff without users:view', async () => {
    servePermissions(mockApi(), matrixWith({ users: { view: false } }))
    renderDialog()

    expect(await screen.findByText("You can't search for people here")).toBeInTheDocument()
  })
})
