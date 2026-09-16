/**
 * setup.ts — runs before every test file (vitest.config.ts `setupFiles`).
 *
 * WHAT IT DOES
 * 1. Registers the jest-dom matchers (`toBeInTheDocument`, `toHaveTextContent`,
 *    …) on Vitest's `expect`, types included.
 * 2. Stubs the browser APIs jsdom does not implement but the app calls during
 *    an ordinary render. Each stub names the caller that needs it.
 * 3. After every test, removes what that test left behind that the next one
 *    could otherwise see: the rendered DOM, localStorage (the session and the
 *    locale) and the permission matrix cached by lib/permissions.ts.
 *
 * WHY cleanup() IS CALLED BY HAND
 * Testing Library unmounts automatically only when the runner exposes a global
 * `afterEach`. This project imports `afterEach` from 'vitest' explicitly and
 * does not enable Vitest globals, so without this call each test would render
 * on top of the previous one's leftovers.
 */
import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach, vi } from 'vitest'
import { resetPermissionCache } from '../lib/permissions'

// ─── Browser APIs jsdom lacks ───

// The chat pages scroll the newest message into view after every load
// (MessagesPage, MarriageChatsPage, StaffChatPage). jsdom has no layout engine
// and does not define scrollIntoView, so the call would throw.
Element.prototype.scrollIntoView = vi.fn()

// ─── Isolation between tests ───

afterEach(() => {
  cleanup()
  localStorage.clear()
  // The matrix is cached at module scope, so without this the first test's
  // reply would answer every later permission check in the same file.
  resetPermissionCache()
})
