/**
 * GroupRoster.test.tsx — the members of one chat group and the staff controls
 * that change them (Phase 6b, OPOS #26399).
 *
 * Pins, through the real components and strings with a mocked `api`:
 *   - the roster: real name (or the "No profile name" fallback), role, and a
 *     masked member's label; removed members behind a toggle;
 *   - remove: a confirmation first, the DELETE, a refresh, and a translated
 *     refusal; nothing is sent when the operator cancels;
 *   - add: the picked person, role and label posted; the refusal codes shown
 *     beside the form; an active member blocked before sending; the
 *     reactivation hint (D3); the users:view guidance card (D2);
 *   - staff without messages:edit see the roster but no controls.
 *
 * askToConfirm is mocked: the confirmation dialog is DialogHost's concern.
 */
import { screen, waitFor, within } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import GroupRoster from './GroupRoster'
import { askToConfirm } from '../../lib/dialogs'
import { EMPLOYEE_USER, matrixWith, servePermissions, serveUserSearch } from '../../test/chatGroupsKit'
import { detailOf, membersUrl, refusal } from '../../test/chatGroupDetailKit'
import { MASKED_GROUP_ID, TEAM_GROUP_ID } from '../../test/fixtures/chatGroups'
import { mockApi } from '../../test/mockApi'
import { renderWithProviders } from '../../test/render'

vi.mock('../../lib/dialogs', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../lib/dialogs')>()),
  askToConfirm: vi.fn(),
}))

beforeEach(() => {
  vi.mocked(askToConfirm).mockReset()
})

const PICK_TIMEOUT_MS = 4000

/** Types a name into the add form's person search and picks the result. */
async function pickPerson(user: UserEvent, fullName: string): Promise<void> {
  const form = screen.getByRole('form', { name: 'Add a member' })
  await user.type(within(form).getByPlaceholderText('Search by name or phone…'), fullName)
  const option = await within(form).findByRole('option', { name: new RegExp(fullName) }, { timeout: PICK_TIMEOUT_MS })
  await user.click(option)
}

function renderRoster(options: { groupId?: number; canEdit?: boolean; onChanged?: () => void } = {}) {
  const group = detailOf(options.groupId ?? MASKED_GROUP_ID)
  const onChanged = options.onChanged ?? vi.fn()
  renderWithProviders(<GroupRoster group={group} canEdit={options.canEdit ?? true} onChanged={onChanged} />)
  return { group, onChanged }
}

describe('GroupRoster — the list', () => {
  it("shows each active member's name, role and masked label, with removed members behind a toggle", async () => {
    const user = userEvent.setup()
    serveUserSearch(servePermissions(mockApi()))
    renderRoster()

    const list = screen.getByRole('list', { name: 'Members' })
    const rows = within(list).getAllByRole('listitem')
    expect(rows).toHaveLength(2)
    expect(within(rows[0]).getByText('Layla Hassan')).toBeInTheDocument()
    expect(within(rows[0]).getByText('Grantor')).toBeInTheDocument()
    expect(within(rows[0]).getByText('Label: Donor 1')).toBeInTheDocument()
    expect(screen.queryByText('Omar Khalid')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Show removed members (1)' }))

    const removed = screen.getByRole('list', { name: 'Removed members' })
    expect(within(removed).getByText('Omar Khalid')).toBeInTheDocument()
    expect(within(removed).getByText('Removed')).toBeInTheDocument()
    expect(within(removed).queryByRole('button', { name: /Remove/ })).not.toBeInTheDocument()
  })

  it('names a member without a profile name by a translated fallback, and shows no label in a team group', () => {
    serveUserSearch(servePermissions(mockApi()))
    const group = detailOf(TEAM_GROUP_ID)
    group.members[0] = { ...group.members[0], full_name: null }
    renderWithProviders(<GroupRoster group={group} canEdit onChanged={vi.fn()} />)

    expect(screen.getByText('No profile name')).toBeInTheDocument()
    expect(screen.queryByText(/^Label:/)).not.toBeInTheDocument()
  })

  it('hides every control from staff without messages:edit and says why', async () => {
    const api = servePermissions(mockApi(), matrixWith({ messages: { edit: false } }))
    renderRoster({ canEdit: false })

    expect(screen.getByText('Layla Hassan')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /^Remove/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('form', { name: 'Add a member' })).not.toBeInTheDocument()
    expect(screen.getByText('Your access level can view the members but not change them.')).toBeInTheDocument()
    expect(api.callsTo('delete', `${membersUrl(MASKED_GROUP_ID)}/101`)).toHaveLength(0)
  })
})

describe('GroupRoster — remove', () => {
  it('asks first, then removes the member and refreshes the group', async () => {
    const user = userEvent.setup()
    vi.mocked(askToConfirm).mockResolvedValue(true)
    const api = serveUserSearch(servePermissions(mockApi())).on('delete', `${membersUrl(MASKED_GROUP_ID)}/101`, {
      data: { success: true },
    })
    const { onChanged } = renderRoster()

    await user.click(screen.getByRole('button', { name: 'Remove Layla Hassan' }))

    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1))
    expect(askToConfirm).toHaveBeenCalledWith(expect.objectContaining({ destructive: true, title: 'Remove member' }))
    expect(api.callsTo('delete', `${membersUrl(MASKED_GROUP_ID)}/101`)).toHaveLength(1)
    expect(await screen.findByText('Member removed')).toBeInTheDocument()
  })

  it('sends nothing when the operator cancels', async () => {
    const user = userEvent.setup()
    vi.mocked(askToConfirm).mockResolvedValue(false)
    const api = serveUserSearch(servePermissions(mockApi()))
    const { onChanged } = renderRoster()

    await user.click(screen.getByRole('button', { name: 'Remove Layla Hassan' }))

    await waitFor(() => expect(askToConfirm).toHaveBeenCalled())
    expect(api.callsTo('delete', `${membersUrl(MASKED_GROUP_ID)}/101`)).toHaveLength(0)
    expect(onChanged).not.toHaveBeenCalled()
  })

  it('shows a refusal in words, never the server text', async () => {
    const user = userEvent.setup()
    vi.mocked(askToConfirm).mockResolvedValue(true)
    serveUserSearch(servePermissions(mockApi())).on(
      'delete',
      `${membersUrl(MASKED_GROUP_ID)}/101`,
      refusal(404, 'group_not_found'),
    )
    renderRoster()

    await user.click(screen.getByRole('button', { name: 'Remove Layla Hassan' }))

    expect(await screen.findByText('This chat group no longer exists. Go back to the list and refresh it.')).toBeInTheDocument()
    expect(screen.queryByText('English server text.')).not.toBeInTheDocument()
  })
})

describe('GroupRoster — add', () => {
  it('posts the picked person, role and trimmed label, then refreshes', async () => {
    const user = userEvent.setup()
    const api = serveUserSearch(servePermissions(mockApi())).on('post', membersUrl(MASKED_GROUP_ID), {
      data: { success: true },
    })
    const { onChanged } = renderRoster()
    const form = screen.getByRole('form', { name: 'Add a member' })
    const submit = within(form).getByRole('button', { name: 'Add member' })
    expect(submit).toBeDisabled()

    await pickPerson(user, 'Noor Jabbar')
    await user.selectOptions(within(form).getByRole('combobox', { name: 'Role in the group' }), 'volunteer')
    await user.type(within(form).getByRole('textbox', { name: 'Label shown to other members' }), ' Helper ')
    await user.click(submit)

    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1))
    expect(api.callsTo('post', membersUrl(MASKED_GROUP_ID))[0].data).toEqual({
      user_id: 106,
      role_in_group: 'volunteer',
      label: 'Helper',
    })
    expect(await screen.findByText('Member added')).toBeInTheDocument()
  })

  it('blocks someone who is already an active member before anything is sent', async () => {
    const user = userEvent.setup()
    const api = serveUserSearch(servePermissions(mockApi()))
    renderRoster()

    await pickPerson(user, 'Layla Hassan')

    expect(await screen.findByText('This person is already an active member of this group.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add member' })).toBeDisabled()
    expect(api.callsTo('post', membersUrl(MASKED_GROUP_ID))).toHaveLength(0)
  })

  it('says a removed member comes back with their old label (D3)', async () => {
    const user = userEvent.setup()
    serveUserSearch(servePermissions(mockApi()))
    renderRoster()

    await pickPerson(user, 'Omar Khalid')

    expect(
      await screen.findByText('This person was removed earlier. Adding them back restores their old role and label.'),
    ).toBeInTheDocument()
  })

  it('shows a label conflict beside the form and keeps what was typed', async () => {
    const user = userEvent.setup()
    serveUserSearch(servePermissions(mockApi())).on(
      'post',
      membersUrl(MASKED_GROUP_ID),
      refusal(409, 'group_label_conflict'),
    )
    const { onChanged } = renderRoster()
    const form = screen.getByRole('form', { name: 'Add a member' })

    await pickPerson(user, 'Noor Jabbar')
    await user.selectOptions(within(form).getByRole('combobox', { name: 'Role in the group' }), 'volunteer')
    await user.click(within(form).getByRole('button', { name: 'Add member' }))

    expect(await within(form).findByRole('alert')).toHaveTextContent(
      "Another member of this group already has this label. Each member's label must be different.",
    )
    expect(within(form).getByRole('combobox', { name: 'Role in the group' })).toHaveValue('volunteer')
    expect(onChanged).not.toHaveBeenCalled()
  })

  it('offers the users:view guidance card instead of a search box (D2)', async () => {
    servePermissions(mockApi(), matrixWith({ users: { view: false } }))
    renderWithProviders(<GroupRoster group={detailOf(MASKED_GROUP_ID)} canEdit onChanged={vi.fn()} />, {
      user: EMPLOYEE_USER,
    })

    expect(await screen.findByText("You can't search for people here")).toBeInTheDocument()
    expect(screen.queryByPlaceholderText('Search by name or phone…')).not.toBeInTheDocument()
  })
})
