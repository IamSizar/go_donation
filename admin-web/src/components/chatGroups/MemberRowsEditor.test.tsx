/**
 * MemberRowsEditor.test.tsx — the member rows inside the create-group dialog.
 *
 * Pins, through the real editor, UserPicker and i18n strings:
 *   - rows are added and removed, and removing one keeps the others' input;
 *   - the role select offers exactly donor, beneficiary, volunteer and staff
 *     for a masked group, in the dashboard's own words for them, and only
 *     volunteer and staff for a team group, with one line saying why;
 *   - the label box exists only for a masked group;
 *   - staff without users:view get a guidance card instead of a search box
 *     they could not use (decision D2), and staff with it get the search box;
 *   - an issue handed in is drawn on its field, with aria-invalid.
 *
 * A small stateful harness owns the rows, the way CreateGroupDialog does.
 */
import { useState } from 'react'
import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import MemberRowsEditor from './MemberRowsEditor'
import type { MemberDraft, MemberRowIssues } from '../../lib/chatGroupForm'
import type { ChatGroupKind } from '../../lib/chatGroupsApi'
import {
  EMPLOYEE_USER, labelBox, matrixWith, memberRow, servePermissions,
} from '../../test/chatGroupsKit'
import { mockApi } from '../../test/mockApi'
import { renderWithProviders } from '../../test/render'

const SEARCH_PLACEHOLDER = 'Search by name or phone…'

/** A row nobody has filled in yet. */
function blankRow(key: string): MemberDraft {
  return { key, user: null, role: '', label: '' }
}

type HarnessProps = {
  kind: ChatGroupKind
  initial?: MemberDraft[]
  issues?: Record<string, MemberRowIssues>
}

/** Owns the rows the way CreateGroupDialog does. */
function Harness({ kind, initial = [blankRow('m1')], issues = {} }: HarnessProps) {
  const [rows, setRows] = useState(initial)
  return <MemberRowsEditor kind={kind} rows={rows} issues={issues} onRowsChange={setRows} onTouch={() => {}} />
}

describe('MemberRowsEditor', () => {
  it('adds a row, and removing the first row keeps what was typed in the second', async () => {
    // Arrange
    const user = userEvent.setup()
    servePermissions(mockApi())
    renderWithProviders(<Harness kind="masked" />)

    // Act
    await user.click(screen.getByRole('button', { name: 'Add member' }))
    await user.type(labelBox(2), 'Second')
    await user.click(screen.getByRole('button', { name: 'Remove member 1' }))

    // Assert: one row is left, renumbered, holding the second row's label.
    expect(screen.queryByRole('group', { name: 'Member 2' })).not.toBeInTheDocument()
    expect(labelBox(1)).toHaveValue('Second')
  }, 15_000)

  it("offers exactly the four roles for a masked group, in the dashboard's words for them", async () => {
    // Arrange
    const user = userEvent.setup()
    servePermissions(mockApi())
    renderWithProviders(<Harness kind="masked" />)
    const select = within(memberRow(1)).getByRole('combobox', { name: 'Role in the group' })

    // Act
    await user.selectOptions(select, 'staff')

    // Assert
    const options = within(select).getAllByRole('option') as HTMLOptionElement[]
    expect(options.map((o) => o.value)).toEqual(['', 'donor', 'beneficiary', 'volunteer', 'staff'])
    expect(options.map((o) => o.textContent)).toEqual(['Choose a role', 'Grantor', 'Recipient', 'Volunteer', 'Staff'])
    expect(select).toHaveValue('staff')
  })

  it('offers only volunteer and staff for a team group, and says why', async () => {
    // A team group shows real names, so the server refuses a grantor or a
    // recipient in one. The form must not offer what would be refused.
    // Arrange
    servePermissions(mockApi())
    renderWithProviders(<Harness kind="team" />)
    const select = within(memberRow(1)).getByRole('combobox', { name: 'Role in the group' })

    // Assert
    const options = within(select).getAllByRole('option') as HTMLOptionElement[]
    expect(options.map((o) => o.value)).toEqual(['', 'volunteer', 'staff'])
    expect(
      screen.getByText('A team group shows real names, so it is for volunteers and staff only.'),
    ).toBeInTheDocument()
  })

  it('asks for a label in a masked group and not in a team group', () => {
    // Arrange + Act
    servePermissions(mockApi())
    const masked = renderWithProviders(<Harness kind="masked" />)

    // Assert
    expect(labelBox(1)).toBeInTheDocument()
    masked.unmount()

    renderWithProviders(<Harness kind="team" />)
    expect(within(memberRow(1)).queryByRole('textbox', { name: 'Label shown to other members' })).toBeNull()
  })

  it('shows a guidance card instead of the search box to staff who cannot view users', async () => {
    // Arrange
    servePermissions(mockApi(), matrixWith({ users: { view: false } }))

    // Act
    renderWithProviders(<Harness kind="masked" />, { user: EMPLOYEE_USER })

    // Assert
    expect(await screen.findByText("You can't search for people here")).toBeInTheDocument()
    expect(screen.queryByPlaceholderText(SEARCH_PLACEHOLDER)).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Add member' })).not.toBeInTheDocument()
  })

  it('shows the search box to an employee whose matrix allows viewing users', async () => {
    // Arrange: the tier alone would deny it, so only the matrix can allow it.
    servePermissions(mockApi(), matrixWith({ users: { view: true } }))

    // Act
    renderWithProviders(<Harness kind="masked" />, { user: EMPLOYEE_USER })

    // Assert
    expect(await screen.findByPlaceholderText(SEARCH_PLACEHOLDER)).toBeInTheDocument()
    expect(screen.queryByText("You can't search for people here")).not.toBeInTheDocument()
  })

  it('draws each issue on its own field', () => {
    // Arrange
    servePermissions(mockApi())
    const issues: Record<string, MemberRowIssues> = {
      m1: {
        user: { key: 'chat_groups.form.member_user_required' },
        role: { key: 'chat_groups.form.member_role_required' },
        label: { key: 'chat_groups.form.label_too_long', vars: { max: 100 } },
      },
    }

    // Act
    renderWithProviders(<Harness kind="masked" issues={issues} />)

    // Assert
    const row = memberRow(1)
    const role = within(row).getByRole('combobox', { name: 'Role in the group' })
    expect(within(row).getByText('Choose a person for this member, or remove the row.')).toBeInTheDocument()
    expect(role).toHaveAttribute('aria-invalid', 'true')
    expect(role).toHaveAccessibleDescription('Choose a role for this member.')
    expect(labelBox(1)).toHaveAttribute('aria-invalid', 'true')
    expect(labelBox(1)).toHaveAccessibleDescription(/Use 100 characters or fewer\./)
  })

  it('shows the contact-detail hint without marking the label invalid', () => {
    // Arrange
    servePermissions(mockApi())
    const issues: Record<string, MemberRowIssues> = {
      m1: { labelHint: { key: 'chat_groups.form.label_contact_hint' } },
    }

    // Act
    renderWithProviders(<Harness kind="masked" issues={issues} />)

    // Assert
    expect(labelBox(1)).not.toHaveAttribute('aria-invalid')
    expect(labelBox(1)).toHaveAccessibleDescription(/looks like a phone number or email address/)
  })
})
