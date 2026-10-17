/**
 * AppShell.nav.test.tsx — exactly one sidebar item is current at a time.
 *
 * '/chat-groups' is a path prefix of '/chat-groups/connect-requests', so a
 * plain NavLink lit both rows (client report #91). Rendered through the real
 * AppShell with the real nav layout.
 */
import { screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import AppShell from './AppShell'
import { mockApi } from '../test/mockApi'
import { renderWithProviders } from '../test/render'

// The sound menu needs the live-alerts provider; irrelevant to the nav.
vi.mock('./SoundMenu', () => ({ default: () => null }))

function currentItems(): string[] {
  return Array.from(document.querySelectorAll('aside.sidebar [aria-current="page"]')).map(
    (el) => el.getAttribute('href') ?? '',
  )
}

describe('AppShell sidebar active state', () => {
  it.each([
    ['/chat-groups', '/chat-groups'],
    ['/chat-groups/connect-requests', '/chat-groups/connect-requests'],
  ])('marks only one item current at %s', async (route, expected) => {
    mockApi()
      .on('get', /.*/, { status: 500, data: {} })
    renderWithProviders(<AppShell />, { route })
    await waitFor(() => expect(currentItems().length).toBeGreaterThan(0))
    expect(currentItems()).toEqual([expected])
    // Only one animated active pill, too.
    expect(document.querySelectorAll('aside.sidebar .nav-active-bg')).toHaveLength(1)
    expect(screen.getAllByRole('link').length).toBeGreaterThan(1)
  })
})
