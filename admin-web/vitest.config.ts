/**
 * vitest.config.ts — how `npm test` runs admin-web's component and unit tests.
 *
 * WHAT IT CONTAINS
 * The app's own vite.config.ts, merged with the test-only settings below, so a
 * test compiles JSX and resolves modules the same way `npm run dev` and
 * `npm run build` do. A hand-kept copy of the plugin list would be a second
 * place for the two to drift apart.
 *
 * HOW IT FITS
 * - environment 'jsdom': components render into a simulated DOM, not a browser.
 * - setupFiles: src/test/setup.ts registers the jest-dom matchers and resets
 *   shared state (DOM, localStorage, the permission cache) after every test.
 * - include: only `*.test.ts(x)` under src/. The zero-dependency node:test
 *   scripts in scripts/ keep their own runner (`npm run test:nav` and friends).
 * - restoreMocks: every vi.spyOn is undone after each test, so an API reply
 *   registered in one test can never answer a request in the next.
 */
import { defineConfig, mergeConfig } from 'vitest/config'
import viteConfig from './vite.config'

export default mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      environment: 'jsdom',
      setupFiles: ['./src/test/setup.ts'],
      include: ['src/**/*.test.{ts,tsx}'],
      restoreMocks: true,
    },
  }),
)
