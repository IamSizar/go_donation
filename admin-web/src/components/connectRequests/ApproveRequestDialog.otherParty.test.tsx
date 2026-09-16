/**
 * ApproveRequestDialog.otherParty.test.tsx — the OTHER PARTY in the approve
 * dialog: the person the case or campaign behind the request belongs to.
 *
 * WHY THIS EXISTS
 * A donor asked to connect from a beneficiary case and the group opened with
 * the donor alone — nobody to talk to. The server now adds the other party
 * itself on approve; the dialog shows them so staff can SEE who is going in,
 * and can swap them for someone else.
 *
 * WHAT IT PINS
 *   - the other party is pre-filled as member 2, under their name when the
 *     server sent one (D6) and as their id when it did not;
 *   - member 2 is removable, and the draft without them still submits — the
 *     requester, member 1, stays non-removable as before;
 *   - a request with no other party (a general-fund donation) opens with the
 *     requester alone, exactly as it did before.
 */
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import ApproveRequestDialog from './ApproveRequestDialog'
import { chooseRole, memberRow, servePermissions, serveUserSearch } from '../../test/chatGroupsKit'
import { CONNECT_REQUESTS } from '../../test/fixtures/chatGroups'
import type { ConnectRequest } from '../../lib/chatGroupsApi'
import { mockApi, type MockApi } from '../../test/mockApi'
import { renderWithProviders } from '../../test/render'

/** A case request whose other party the server resolved and named. */
const REQUEST: ConnectRequest = {
  ...CONNECT_REQUESTS[1],
  requester_name: 'Sara Ali',
  other_party_user_id: 205,
  other_party_name: 'Hana Omar',
}
const APPROVE_URL = `/api/admin/chat-groups/connect-requests/${REQUEST.id}/approve`

function readyApi(): MockApi {
  return serveUserSearch(servePermissions(mockApi()))
}

function renderDialog(request: ConnectRequest = REQUEST) {
  const onApproved = vi.fn()
  renderWithProviders(
    <ApproveRequestDialog request={request} onClose={vi.fn()} onApproved={onApproved} />,
  )
  return { onApproved }
}

const approveButton = () => screen.getByRole('button', { name: 'Approve and open group' })

describe('ApproveRequestDialog — the other party', () => {
  it('pre-fills the requester and the other party, and sends both', async () => {
    const user = userEvent.setup()
    const api = readyApi().on('post', APPROVE_URL, { data: { success: true, group_id: 100011 } })
    const { onApproved } = renderDialog()

    expect(memberRow(1)).toHaveTextContent('Sara Ali')
    expect(memberRow(2)).toHaveTextContent('Hana Omar')

    await user.click(screen.getByRole('radio', { name: /Masked group/ }))
    await chooseRole(user, 1, 'donor')
    await chooseRole(user, 2, 'beneficiary')
    await user.click(approveButton())

    await waitFor(() => expect(onApproved).toHaveBeenCalledWith(100011))
    expect(api.callsTo('post', APPROVE_URL).map((c) => c.data)).toEqual([
      {
        kind: 'masked',
        member_title: '',
        members: [
          { user_id: REQUEST.requester_user_id, role_in_group: 'donor', label: '' },
          { user_id: 205, role_in_group: 'beneficiary', label: '' },
        ],
      },
    ])
  })

  it('lets staff remove the other party and still submit', async () => {
    const user = userEvent.setup()
    const api = readyApi().on('post', APPROVE_URL, { data: { success: true, group_id: 100012 } })
    const { onApproved } = renderDialog()

    await user.click(screen.getByRole('radio', { name: /Masked group/ }))
    await chooseRole(user, 1, 'donor')
    await user.click(screen.getByRole('button', { name: 'Remove member 2' }))
    await user.click(approveButton())

    await waitFor(() => expect(onApproved).toHaveBeenCalledWith(100012))
    expect(api.callsTo('post', APPROVE_URL).map((c) => c.data)).toEqual([
      {
        kind: 'masked',
        member_title: '',
        members: [{ user_id: REQUEST.requester_user_id, role_in_group: 'donor', label: '' }],
      },
    ])
  })

  it('opens with the requester alone when the request has no other party', async () => {
    readyApi()
    renderDialog({ ...CONNECT_REQUESTS[1], requester_name: 'Sara Ali' })

    expect(memberRow(1)).toHaveTextContent('Sara Ali')
    expect(screen.queryByRole('button', { name: 'Remove member 2' })).not.toBeInTheDocument()
  })
})
