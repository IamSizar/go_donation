/**
 * GroupContactBlocks.test.tsx — the refused contact-sharing attempts in one
 * chat group: the list with each kind's label, the reassuring empty state,
 * and a failed load that recovers through Try again.
 */
import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import GroupContactBlocks from './GroupContactBlocks'
import { blocksUrl } from '../../test/chatGroupDetailKit'
import { CHAT_GROUP_CONTACT_BLOCKS, MASKED_GROUP_ID, TEAM_GROUP_ID } from '../../test/fixtures/chatGroups'
import { mockApi } from '../../test/mockApi'
import { renderWithProviders } from '../../test/render'

describe('GroupContactBlocks', () => {
  it('lists each refusal with its sender, kind label and redacted body', async () => {
    mockApi().on('get', blocksUrl(MASKED_GROUP_ID), {
      data: { success: true, items: CHAT_GROUP_CONTACT_BLOCKS[MASKED_GROUP_ID] },
    })

    renderWithProviders(<GroupContactBlocks groupId={MASKED_GROUP_ID} />)

    expect(screen.getByText('Loading blocked attempts…')).toBeInTheDocument()
    expect(await screen.findByText('My number is ••• or email ••• if that is easier')).toBeInTheDocument()
    expect(screen.getByText('Phone and email')).toBeInTheDocument()
    expect(screen.getByText('Phone number')).toBeInTheDocument()
    expect(screen.getAllByText('Omar Khalid')).toHaveLength(2)
  })

  it('says nothing was blocked when the group is clean', async () => {
    mockApi().on('get', blocksUrl(TEAM_GROUP_ID), { data: { success: true, items: [] } })

    renderWithProviders(<GroupContactBlocks groupId={TEAM_GROUP_ID} />)

    expect(await screen.findByText('Nothing has been blocked in this conversation.')).toBeInTheDocument()
  })

  it('shows the translated failure and recovers on Try again', async () => {
    const user = userEvent.setup()
    const api = mockApi().on('get', blocksUrl(TEAM_GROUP_ID), { status: 500, data: { success: false, error: 'Database error.' } })
    renderWithProviders(<GroupContactBlocks groupId={TEAM_GROUP_ID} />)
    expect(await screen.findByText('A server error occurred. Please try again in a moment.')).toBeInTheDocument()

    api.on('get', blocksUrl(TEAM_GROUP_ID), { data: { success: true, items: [] } })
    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(await screen.findByText('Nothing has been blocked in this conversation.')).toBeInTheDocument()
  })
})
