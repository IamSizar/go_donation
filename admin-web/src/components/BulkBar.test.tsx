/**
 * BulkBar.test.tsx — delete-only mode (omitting `allowed`/`onApply`) renders no
 * status select or Apply button, keeps the confirmation dialog before deleting,
 * and leaves the status mode of existing callers unchanged.
 */
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import BulkBar from './BulkBar'
import { renderWithProviders } from '../test/render'

describe('BulkBar', () => {
  it('delete-only: no status select or Apply; delete asks first, then runs', async () => {
    const onDelete = vi.fn().mockResolvedValue({ ok: 2, fail: 0 })
    const user = userEvent.setup()
    renderWithProviders(<BulkBar count={2} onDelete={onDelete} onClear={() => {}} noun="rows" />)

    expect(screen.queryByRole('combobox')).toBeNull()
    expect(screen.queryByRole('button', { name: 'Apply' })).toBeNull()

    await user.click(screen.getByRole('button', { name: /Delete 2/ }))
    expect(onDelete).not.toHaveBeenCalled() // confirmation dialog first
    const dialog = screen.getByRole('alertdialog')
    await user.click(Array.from(dialog.querySelectorAll('button')).find((b) => /Delete 2/.test(b.textContent ?? ''))!)
    await waitFor(() => expect(onDelete).toHaveBeenCalledTimes(1))
  })

  it('status mode is unchanged: select + Apply are shown', () => {
    renderWithProviders(
      <BulkBar count={1} allowed={['active', 'hidden']} onApply={vi.fn()} onClear={() => {}} />,
    )
    expect(screen.getByRole('combobox')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Apply' })).toBeTruthy()
  })
})
