/**
 * permissions.test.ts — resetPermissionCache(), the test seam in lib/permissions.ts.
 *
 * lib/permissions.ts caches the permission matrix at module scope, which is
 * right for the app (one fetch per page load) and wrong for a test file: every
 * test after the first would be answered from the first test's matrix. This
 * pins that resetPermissionCache() really forgets it, by proving the hook
 * fetches again and uses the NEW answer.
 *
 * The user is a super_admin on purpose. That tier's fallback (used before a
 * matrix arrives) is "allowed", so a `false` can only come from the matrix
 * itself, and a `true` after the reset can only come from the second matrix if
 * the stale `false` was really forgotten.
 */
import { renderHook, waitFor } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { resetPermissionCache, useExportAllowed } from './permissions'
import { MOCK_STAFF_USER } from '../test/fixtures/session'
import { mockApi } from '../test/mockApi'

const ME_URL = '/api/admin/permissions/me'

/** A GET /api/admin/permissions/me reply whose only answer is users:export. */
function matrixWithUsersExport(allowed: boolean) {
  return {
    data: { success: true, tier: 'super_admin', permissions: { users: { view: true, export: allowed } } },
  }
}

describe('resetPermissionCache', () => {
  it('makes the next hook fetch the matrix again instead of answering from the old one', async () => {
    // Arrange: the first matrix refuses exporting users, and the hook uses it.
    const api = mockApi().on('get', ME_URL, matrixWithUsersExport(false))
    const first = renderHook(() => useExportAllowed('users', MOCK_STAFF_USER))
    await waitFor(() => expect(first.result.current).toBe(false))
    first.unmount()

    // Act: forget the matrix, and have the server grant the permission.
    resetPermissionCache()
    api.on('get', ME_URL, matrixWithUsersExport(true))
    const second = renderHook(() => useExportAllowed('users', MOCK_STAFF_USER))

    // Assert: a second request went out and its answer is the one in use.
    await waitFor(() => expect(second.result.current).toBe(true))
    expect(api.callsTo('get', ME_URL)).toHaveLength(2)
  })
})
