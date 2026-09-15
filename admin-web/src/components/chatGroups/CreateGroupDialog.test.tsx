/**
 * CreateGroupDialog.test.tsx — creating a chat group, from the kind cards to
 * the POST body and back.
 *
 * Pins, through the real dialog, the real member editor and UserPicker, the
 * real i18n strings and a mocked `api`:
 *   - the exact body POST /api/admin/chat-groups receives for each kind: a
 *     masked group sends member_title '' and trimmed labels, a team group
 *     sends a trimmed title and labels '';
 *   - Create group stays disabled while the form breaks a rule, so a doomed
 *     request never fires;
 *   - a broken rule is named beside its field, not only after a submit;
 *   - a coded refusal (400 guest_member_not_allowed, 409 group_label_conflict)
 *     is translated and shown beside the members, and the dialog stays open;
 *   - success closes the dialog, confirms with a toast and refreshes the list.
 */
import { screen, waitFor, within } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import CreateGroupDialog from './CreateGroupDialog'
import ChatGroupsPage from '../../pages/ChatGroupsPage'
import {
  chooseRole, labelBox, memberRow, pickPerson, servePermissions, serveUserSearch,
} from '../../test/chatGroupsKit'
import { mockApi, type MockApi } from '../../test/mockApi'
import { renderWithProviders } from '../../test/render'

const GROUPS_URL = '/api/admin/chat-groups'

// ─── Arrange helpers ───

/** A mock API that answers the permission matrix and the users search. */
function readyApi(): MockApi {
  return serveUserSearch(servePermissions(mockApi()))
}

/** Renders the dialog on its own, with spies for both callbacks. */
function renderDialog() {
  const onClose = vi.fn()
  const onCreated = vi.fn()
  renderWithProviders(<CreateGroupDialog onClose={onClose} onCreated={onCreated} />)
  return { onClose, onCreated }
}

function createButton(): HTMLElement {
  return screen.getByRole('button', { name: 'Create group' })
}

/** Fills a valid masked group: Layla as a labelled donor, Sara unlabelled. */
async function fillMaskedGroup(user: UserEvent): Promise<void> {
  await user.click(screen.getByRole('radio', { name: /Masked group/ }))
  await pickPerson(user, 1, 'Layla Hassan')
  await chooseRole(user, 1, 'donor')
  await user.type(labelBox(1), ' Donor A ')
  await user.click(screen.getByRole('button', { name: 'Add member' }))
  await pickPerson(user, 2, 'Sara Ali')
  await chooseRole(user, 2, 'beneficiary')
}

/** Fills a valid team group with one volunteer. */
async function fillTeamGroup(user: UserEvent, title: string): Promise<void> {
  await user.click(screen.getByRole('radio', { name: /Team group/ }))
  await user.type(screen.getByRole('textbox', { name: 'Team name' }), title)
  await pickPerson(user, 1, 'Yusuf Kareem')
  await chooseRole(user, 1, 'volunteer')
}

// ─── Tests ───

describe('CreateGroupDialog', () => {
  it("sends a masked group with an empty title and each member's trimmed label", async () => {
    // Arrange
    const user = userEvent.setup()
    const api = readyApi().on('post', GROUPS_URL, { data: { success: true, group_id: 100001 } })
    const { onCreated } = renderDialog()

    // Act
    await fillMaskedGroup(user)
    await user.click(createButton())

    // Assert
    await waitFor(() => expect(onCreated).toHaveBeenCalledWith(100001))
    expect(api.callsTo('post', GROUPS_URL)).toEqual([
      {
        method: 'post',
        url: GROUPS_URL,
        data: {
          kind: 'masked',
          member_title: '',
          members: [
            { user_id: 101, role_in_group: 'donor', label: 'Donor A' },
            { user_id: 103, role_in_group: 'beneficiary', label: '' },
          ],
        },
      },
    ])
  }, 15_000)

  it('sends a team group with its trimmed title and no labels', async () => {
    // Arrange
    const user = userEvent.setup()
    const api = readyApi().on('post', GROUPS_URL, { data: { success: true, group_id: 100002 } })
    const { onCreated } = renderDialog()

    // Act
    await fillTeamGroup(user, '  Distribution volunteers  ')
    expect(within(memberRow(1)).queryByRole('textbox', { name: 'Label shown to other members' })).toBeNull()
    await user.click(createButton())

    // Assert
    await waitFor(() => expect(onCreated).toHaveBeenCalledWith(100002))
    expect(api.callsTo('post', GROUPS_URL).map((c) => c.data)).toEqual([
      {
        kind: 'team',
        member_title: 'Distribution volunteers',
        members: [{ user_id: 105, role_in_group: 'volunteer', label: '' }],
      },
    ])
  }, 15_000)

  it('keeps Create group disabled until every rule is met, so nothing doomed is sent', async () => {
    // Arrange
    const user = userEvent.setup()
    const api = readyApi()
    renderDialog()

    // Act + Assert, one step at a time.
    expect(createButton()).toBeDisabled()
    await user.click(screen.getByRole('radio', { name: /Masked group/ }))
    expect(createButton()).toBeDisabled()
    await pickPerson(user, 1, 'Layla Hassan')
    expect(createButton()).toBeDisabled()
    await chooseRole(user, 1, 'donor')
    expect(createButton()).toBeEnabled()

    // The same person twice breaks a rule again.
    await user.click(screen.getByRole('button', { name: 'Add member' }))
    await pickPerson(user, 2, 'Layla Hassan')
    await chooseRole(user, 2, 'donor')
    expect(createButton()).toBeDisabled()
    expect(within(memberRow(2)).getByText('This person is already in the group. Remove this row.')).toBeInTheDocument()

    await user.click(createButton())
    expect(api.callsTo('post', GROUPS_URL)).toHaveLength(0)
  }, 15_000)

  it('names a broken rule beside its field as the operator types', async () => {
    // Arrange
    const user = userEvent.setup()
    readyApi()
    renderDialog()
    await user.click(screen.getByRole('radio', { name: /Team group/ }))
    const title = screen.getByRole('textbox', { name: 'Team name' })

    // Act: type, then clear, the team name.
    await user.type(title, 'x')
    await user.clear(title)

    // Assert
    expect(title).toHaveAttribute('aria-invalid', 'true')
    expect(title).toHaveAccessibleDescription(/Enter a name for the team group\./)

    // Act: a name one character too long.
    await user.click(title)
    await user.paste('a'.repeat(201))
    expect(title).toHaveAccessibleDescription(/Use 200 characters or fewer\./)

    // Act: a masked label one character too long.
    await user.click(screen.getByRole('radio', { name: /Masked group/ }))
    await user.click(labelBox(1))
    await user.paste('b'.repeat(101))
    expect(labelBox(1)).toHaveAttribute('aria-invalid', 'true')
    expect(labelBox(1)).toHaveAccessibleDescription(/Use 100 characters or fewer\./)
  }, 15_000)

  it.each([
    {
      status: 400,
      code: 'guest_member_not_allowed',
      english: 'Guest accounts cannot be added to a chat group.',
      shown: 'Guest accounts cannot join a chat group. Remove the guest account from the members and try again.',
    },
    {
      status: 409,
      code: 'group_label_conflict',
      english: 'Duplicate label.',
      shown: 'Two members would have the same label. Give each member a different label.',
    },
  ])('explains a $status $code beside the members and keeps the dialog open', async ({ status, code, english, shown }) => {
    // Arrange
    const user = userEvent.setup()
    readyApi().on('post', GROUPS_URL, { status, data: { success: false, error: english, code } })
    const { onCreated } = renderDialog()

    // Act
    await fillMaskedGroup(user)
    await user.click(createButton())

    // Assert
    const members = screen.getByRole('group', { name: 'Members' })
    expect(await within(members).findByText(shown)).toBeInTheDocument()
    expect(screen.queryByText(english)).not.toBeInTheDocument()
    expect(screen.getByRole('dialog', { name: 'New chat group' })).toBeInTheDocument()
    expect(onCreated).not.toHaveBeenCalled()
  }, 15_000)

  it('closes on Escape and on Cancel without sending anything', async () => {
    // Arrange
    const user = userEvent.setup()
    const api = readyApi()
    const { onClose } = renderDialog()

    // Act
    await user.keyboard('{Escape}')
    await user.click(screen.getByRole('button', { name: 'Cancel' }))

    // Assert
    expect(onClose).toHaveBeenCalledTimes(2)
    expect(api.callsTo('post', GROUPS_URL)).toHaveLength(0)
  })

  it('closes, confirms with a toast and refreshes the list after a successful create', async () => {
    // Arrange: the page starts empty, and the server has the new group once
    // the create has gone through.
    const user = userEvent.setup()
    const api = readyApi()
      .on('get', GROUPS_URL, { data: { success: true, items: [] } })
      .on('post', GROUPS_URL, { data: { success: true, group_id: 100003 } })
    renderWithProviders(<ChatGroupsPage />)
    await user.click(await screen.findByRole('button', { name: 'Create a group' }))
    await fillTeamGroup(user, 'Night shift')
    api.on('get', GROUPS_URL, {
      data: {
        success: true,
        items: [{ id: 100003, kind: 'team', title: 'Night shift', unread_count: 0, last_message: '', last_at: '2026-09-15T10:00:00Z' }],
      },
    })

    // Act
    await user.click(createButton())

    // Assert
    // The dialog leaves after its exit animation, which runs on real frames.
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'New chat group' })).not.toBeInTheDocument(), {
      timeout: 4000,
    })
    expect(screen.getByText('Chat group created')).toBeInTheDocument()
    const list = await screen.findByRole('list', { name: 'Chat groups' })
    expect(within(list).getByText('Night shift')).toBeInTheDocument()
    expect(api.callsTo('get', GROUPS_URL)).toHaveLength(2)
  }, 15_000)
})
