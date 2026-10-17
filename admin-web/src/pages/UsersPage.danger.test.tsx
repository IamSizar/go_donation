/**
 * UsersPage.danger.test.tsx — client #77 / #82:
 *  - «حذف الحساب» lives inside the Edit window (danger zone), NOT in the row's
 *    actions menu;
 *  - the list has select-all + a bulk delete bar (Super-Admin).
 */
import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import UsersPage from './UsersPage'
import { mockApi } from '../test/mockApi'
import { renderWithProviders } from '../test/render'

const USER = {
  user_id: 41, phone: '9647701230000', role_id: 1, active: 1, is_admin: 0,
  created_at: '2026-10-01T09:00:00Z', profile: { full_name: 'Dana Salih' },
  staff_tier: 'user', account_status: 'active', is_guest: false, has_password: false,
  wallet_balance_iqd: 0,
}

function setup() {
  return mockApi()
    .on('get', '/api/admin/users', {
      data: { status: 'success', data: [USER], pagination: { total_items: 1, total_pages: 1, page: 1, per_page: 20 } },
    })
    .on('get', /\/api\/admin\/detail\/users\/41/, { data: { item: { ...USER.profile, username: '' } } })
    .on('get', '/api/admin/registration/field-rules', { data: { items: [] } })
}

describe('UsersPage delete placement', () => {
  it('keeps delete out of the row menu and puts it in the edit danger zone', async () => {
    setup()
    renderWithProviders(<UsersPage />)
    const row = (await screen.findByText('Dana Salih')).closest('tr')!
    fireEvent.click(within(row).getByRole('button', { name: /actions|الإجراءات/i }))
    const menu = await screen.findByRole('menu')
    expect(within(menu).queryByText(/^(delete|حذف)$/i)).toBeNull()

    fireEvent.click(within(menu).getByRole('menuitem', { name: /edit|تعديل/i }))
    const del = await screen.findByRole('button', { name: /delete account|حذف الحساب/i })
    expect(del.closest('.danger-zone')).not.toBeNull()
  })

  it('shows select-all and a bulk delete bar once a row is ticked', async () => {
    setup()
    renderWithProviders(<UsersPage />)
    await screen.findByText('Dana Salih')
    const boxes = screen.getAllByRole('checkbox')
    // header select-all + the row (+ the hide-guests filter checkbox)
    fireEvent.click(boxes.find((b) => b.closest('thead'))!)
    await waitFor(() => expect(screen.getByRole('button', { name: /^(delete|حذف)/i })).toBeInTheDocument())
  })
})
