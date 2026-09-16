/**
 * mockApi.ts — stands in for the server inside one test.
 *
 * WHY SPY ON `api` AND NOT THE NETWORK
 * Every component reaches the server through the single `api` axios instance
 * in lib/api.ts. Replacing its get/post/put/patch/delete keeps a test off the
 * real network, needs no extra dependency, and lets the test assert the exact
 * URL, query and body a component sent.
 *
 * WHAT THIS BYPASSES
 * The interceptors in lib/api.ts (the Bearer header, the delete-password
 * dialog, the sign-out on 401) run inside axios's request pipeline, which a
 * spy on `api.delete` never enters. A test ABOUT those interceptors cannot use
 * this helper.
 *
 * FAILING LOUDLY
 * A request with no registered reply rejects with an Error naming the method
 * and URL. A component that shows its error puts that message on screen, so a
 * test waiting for other text fails with the unexpected URL in the DOM dump.
 * A silent default reply would let a component call the wrong URL and pass.
 *
 * vitest.config.ts sets restoreMocks, so the spies are removed after every
 * test with no teardown needed here.
 */
import { AxiosError, AxiosHeaders, type AxiosRequestConfig, type AxiosResponse } from 'axios'
import { vi } from 'vitest'
import { api } from '../lib/api'

// ─── Types ───

/** The HTTP methods a reply can be registered for. */
export type MockMethod = 'get' | 'post' | 'put' | 'patch' | 'delete'

/** One request a component made, as the spy received it. */
export type MockCall = {
  method: MockMethod
  /** The path exactly as the component passed it, without axios `params`. */
  url: string
  /** axios `params` (the query string), when the caller passed any. */
  params?: unknown
  /** The body: POST/PUT/PATCH `data`, or `config.data` for a DELETE. */
  data?: unknown
}

/** What a route answers. Status defaults to 200; 400 and above reject. */
export type MockReply = { status?: number; data?: unknown }

/** A fixed reply, or a function that builds one from the request. */
export type MockHandler = MockReply | ((call: MockCall) => MockReply)

/** The controller {@link mockApi} returns. */
export type MockApi = {
  /**
   * Registers what `method` + `url` answers. `url` is an exact path or a
   * RegExp tested against the path. The LATEST matching registration wins, so
   * a test can change the server's answer between two steps.
   *
   * @returns the same controller, so registrations can be chained.
   */
  on: (method: MockMethod, url: string | RegExp, handler: MockHandler) => MockApi
  /** Every request made so far, oldest first. */
  calls: MockCall[]
  /** The requests made to one method and exact path, oldest first. */
  callsTo: (method: MockMethod, url: string) => MockCall[]
}

type Route = { method: MockMethod; url: string | RegExp; handler: MockHandler }

// ─── Settling one request ───

/** Whether a registered route answers this request. */
function matches(route: Route, call: MockCall): boolean {
  if (route.method !== call.method) return false
  return typeof route.url === 'string' ? route.url === call.url : route.url.test(call.url)
}

/**
 * Resolves with the registered reply, or rejects the way axios itself does for
 * a non-2xx response: an AxiosError carrying `response.status` and
 * `response.data`, which is exactly what describeError() in lib/api.ts reads.
 */
function settle(call: MockCall, routes: Route[]): Promise<AxiosResponse> {
  const route = [...routes].reverse().find((r) => matches(r, call))
  if (!route) {
    return Promise.reject(
      new Error(`mockApi: no reply registered for ${call.method.toUpperCase()} ${call.url}`),
    )
  }
  const reply = typeof route.handler === 'function' ? route.handler(call) : route.handler
  const status = reply.status ?? 200
  const config = { headers: new AxiosHeaders(), method: call.method, url: call.url }
  const response: AxiosResponse = { data: reply.data, status, statusText: '', headers: {}, config }
  if (status < 400) return Promise.resolve(response)

  // axios uses ERR_BAD_REQUEST for 4xx and ERR_BAD_RESPONSE for 5xx.
  const code = status >= 500 ? AxiosError.ERR_BAD_RESPONSE : AxiosError.ERR_BAD_REQUEST
  return Promise.reject(
    new AxiosError(`Request failed with status code ${status}`, code, config, null, response),
  )
}

// ─── Public API ───

/**
 * Replaces the HTTP methods of lib/api.ts's `api` for the current test.
 *
 * Call it at the start of a test, register replies with `on`, then render.
 * Every request is recorded in `calls` whether or not a reply matched it.
 *
 * @returns the controller used to register replies and inspect requests.
 */
export function mockApi(): MockApi {
  const routes: Route[] = []
  const calls: MockCall[] = []

  const record = (call: MockCall): Promise<AxiosResponse> => {
    // Absent params/body are left off the record rather than stored as
    // `undefined`, so a failed toEqual diff shows only the fields that differ.
    const recorded: MockCall = { method: call.method, url: call.url }
    if (call.params !== undefined) recorded.params = call.params
    if (call.data !== undefined) recorded.data = call.data
    calls.push(recorded)
    return settle(recorded, routes)
  }

  // Cast once per method: axios types each method as a generic over the
  // response body, which a single recording function cannot express.
  vi.spyOn(api, 'get').mockImplementation(((url: string, config?: AxiosRequestConfig) =>
    record({ method: 'get', url, params: config?.params })) as typeof api.get)
  vi.spyOn(api, 'delete').mockImplementation(((url: string, config?: AxiosRequestConfig) =>
    record({ method: 'delete', url, params: config?.params, data: config?.data })) as typeof api.delete)
  vi.spyOn(api, 'post').mockImplementation(((url: string, data?: unknown, config?: AxiosRequestConfig) =>
    record({ method: 'post', url, params: config?.params, data })) as typeof api.post)
  vi.spyOn(api, 'put').mockImplementation(((url: string, data?: unknown, config?: AxiosRequestConfig) =>
    record({ method: 'put', url, params: config?.params, data })) as typeof api.put)
  vi.spyOn(api, 'patch').mockImplementation(((url: string, data?: unknown, config?: AxiosRequestConfig) =>
    record({ method: 'patch', url, params: config?.params, data })) as typeof api.patch)

  const controller: MockApi = {
    on(method, url, handler) {
      routes.push({ method, url, handler })
      return controller
    },
    calls,
    callsTo: (method, url) => calls.filter((c) => c.method === method && c.url === url),
  }
  return controller
}
