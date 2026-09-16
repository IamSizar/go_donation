/**
 * InKindPage.test.tsx — the in-kind donations list.
 *
 * Covers one thing only, and deliberately so: client item C3, which asks every
 * dashboard table to print a timestamp as the date on top and the time
 * underneath. This page's Created column was one long line, so this test is
 * the regression that stops it going back — it asserts the rendered cell, not
 * the helper, because the helper was already right and the cell was not.
 *
 * Strings are asserted through formatDateParts rather than hard-coded, since
 * both the cell and the assertion must follow the machine's locale.
 */
import { screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import InKindPage from './InKindPage'
import { formatDateParts } from '../lib/dates'
import { mockApi } from '../test/mockApi'
import { renderWithProviders } from '../test/render'

const LIST_URL = '/api/admin/in_kind_donations'
const CREATED_AT = '2026-09-14T09:00:00Z'

const ITEM = {
  id: 501,
  donor_user_id: 7,
  donor_phone: '07700000000',
  donor_full_name: 'Dana Salih',
  category: 'food_pantry',
  item_name: 'Rice sacks',
  quantity: '12',
  condition_note: null,
  pickup_address: 'Mosul, Al-Nour',
  status: 'submitted',
  notes: null,
  created_at: CREATED_AT,
}

describe('InKindPage', () => {
  it('prints the created timestamp as the date over the time', async () => {
    // Arrange
    mockApi().on('get', LIST_URL, {
      data: { success: true, items: [ITEM], page: 1, per_page: 20, total: 1 },
    })

    // Act
    renderWithProviders(<InKindPage />)

    // Assert
    const row = (await screen.findByText('Rice sacks')).closest('tr')
    expect(row).not.toBeNull()
    const stamp = row!.querySelector('time')
    expect(stamp).not.toBeNull()
    expect(stamp).toHaveAttribute('datetime', CREATED_AT)

    const { date, time } = formatDateParts(CREATED_AT)
    expect(within(stamp!).getByText(date)).toBeInTheDocument()
    expect(within(stamp!).getByText(time)).toBeInTheDocument()
    expect(Array.from(stamp!.querySelectorAll('span')).map((s) => s.textContent)).toEqual([date, time])
  })
})
