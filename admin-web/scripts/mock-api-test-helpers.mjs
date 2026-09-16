// mock-api-test-helpers.mjs — what the mock API's node:test files share.
//
// Imported by scripts/mock-api.test.mjs (shell, legacy chats, scenarios, drift
// guards, network exposure) and scripts/mock-api-chat-groups.test.mjs (the
// chat-group routes). The two files were one until it passed the 500-line
// limit; this keeps them from each carrying a copy of the server set-up.
//
// Not a test file itself: `npm run test:mock-api` names the two test files
// explicitly, so node --test never runs this one.
import { createMockServer, listenOnLoopback } from './mock-api.mjs'

/**
 * Starts a mock server on a free port for one test and returns a request
 * function bound to it. The server is closed when that test ends.
 *
 * @param {import('node:test').TestContext} t  the running test.
 * @param {object} [options]  passed to createMockServer (scenario, slowMs).
 * @returns {Promise<(method: string, path: string, body?: unknown) => Promise<{ status: number, body: any }>>}
 */
export async function startMock(t, options = {}) {
  const server = createMockServer({ log: () => {}, slowMs: 10, ...options })
  await listenOnLoopback(server, 0)
  t.after(
    () =>
      new Promise((resolve) => {
        server.closeAllConnections()
        server.close(resolve)
      }),
  )
  const { port } = server.address()
  return async (method, path, body) => {
    const res = await fetch(`http://127.0.0.1:${port}${path}`, {
      method,
      headers: body === undefined ? {} : { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
    return { status: res.status, body: await res.json() }
  }
}
