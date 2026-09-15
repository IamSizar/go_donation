# Mock API: the dashboard without a backend or a login

`scripts/mock-api.mjs` is a zero-dependency stand-in for the Go API. With it you can open admin-web in a real browser and look at a screen without a database, a running backend or a staff account.

It answers:

- the requests every page makes: permissions, pending counts, events and notifications;
- the users search behind the member picker;
- every chat-group admin route, including connect requests;
- the three older chat systems: donor, marriage and staff chats.

Its data comes from `src/test/fixtures/*.ts`, the same fixtures the component tests use. Any other route answers `{ "success": true, "items": [], "data": [] }`.

## Run it

Use Node 22, as `.nvmrc` says. Open two terminals, both in `admin-web/`:

```sh
npm run mock:api                                                     # terminal 1: 127.0.0.1:8787
API_TARGET=http://127.0.0.1:8787 npm run dev -- --host 127.0.0.1     # terminal 2: Vite proxies /api to the mock
```

To use another port, set `MOCK_API_PORT` for the mock and point `API_TARGET` at the same port. `vite.config.ts` reads `API_TARGET`.

## Who can reach it

**The mock listens on the IPv4 loopback interface, 127.0.0.1, and nowhere else.** Other machines cannot connect to it. This matters because every route answers without credentials and the start-up banner prints a super_admin session.

- **Write 127.0.0.1, not `localhost`.** The mock does not listen on IPv6 (`::1`), so name the address explicitly rather than rely on how a tool resolves `localhost`.
- **Keep Vite on loopback too.** `vite.config.ts` sets `host: true`, so a plain `npm run dev` listens on every interface. Anyone on the same network could then reach the mock's data through Vite's `/api` proxy. The `-- --host 127.0.0.1` above overrides that setting; with it, Vite listens on 127.0.0.1 only.

## Skip the login

`RequireAuth` in `src/lib/auth.tsx` only checks that localStorage holds a token and a user. It never asks the server. The mock never checks the token either.

1. Open the dashboard at http://127.0.0.1:5173.
2. Open the browser console on that tab.
3. Paste the lines below, then reload.

```js
localStorage.setItem('humanitarian.admin.token', 'mock')
localStorage.setItem('humanitarian.admin.user', '{"user_id":1,"phone":"+9647700000001","role_id":null,"is_admin":1,"staff_tier":"super_admin"}')
localStorage.setItem('locale', 'en')
```

| Key | Read by | Value |
|---|---|---|
| `humanitarian.admin.token` | `getToken()` in `src/lib/api.ts` | any non-empty string |
| `humanitarian.admin.user` | `getStoredUser()` in `src/lib/api.ts` | a `StoredUser` as JSON; `super_admin` passes every client-side gate |
| `locale` | `currentLocale()` in `src/lib/i18n.tsx` | `en`, `ar`, `ckb` or `kmr` |

localStorage belongs to one origin. Paste the lines on the same address you browse, 127.0.0.1:5173 as above; a session pasted on `localhost:5173` is not visible on `127.0.0.1:5173`.

The mock prints the same lines when it starts. They are built from `src/test/fixtures/session.ts`, and `npm run test:mock-api` fails if those key names stop matching `api.ts` and `i18n.tsx`.

The session ends like a real one:

- Signing out, or the idle lock after 20 minutes, clears these keys and sends you to `/login`.
- To get back in, paste the lines again.
- To sign out by hand, run `localStorage.clear()` and reload.

## Scenarios

| Scenario | What a request gets |
|---|---|
| `default` | The fixtures. Sent messages, added or removed members, approvals, declines and lifecycle changes are kept in memory until the mock restarts. |
| `empty` | Every top-level list is empty and every total is 0. Objects such as the permission matrix, a group's roster and the pending counts are unchanged. |
| `error` | `500 { "success": false, "error": "Database error." }` |
| `slow` | The default answer, 2 seconds late. |

- **Whole run:** `MOCK_SCENARIO=empty npm run mock:api`.
- **One request:** add `?scenario=error` to the URL, which is handy with curl. `?scenario=default` overrides `MOCK_SCENARIO` for that request.
- **Unknown names:** the request answers 400, so a typo can't pass for the default.

Every request is logged, for example:

```text
[mock-api] GET /api/admin/chat-groups -> 200 (default)
```

## Deletes

Every admin DELETE asks for the operator's password first; the interceptor lives in `src/lib/api.ts`. The mock accepts any password, so type anything.

## Check it

```sh
npm run test:mock-api
curl -s http://127.0.0.1:8787/api/admin/chat-groups
curl -s 'http://127.0.0.1:8787/api/admin/chat-groups/41/messages?after_id=8101&limit=2'
```

`npm run test:mock-api` (node --test) checks the route shapes, the scenarios, that the server binds to loopback only, and two drift guards.

What the fixtures contain:

| Area | Ids |
|---|---|
| Masked group | 41 |
| Team group | 42 |
| Guest account | user 107, "Guest visitor". The users search finds it, and creating a group with it, or adding it to one, answers 400 `guest_member_not_allowed` |
| Connect requests | 29 (declined), 30 (approved), 31 and 32 (pending) |
| Donor chats | 7 (active), 8 (paused), 9 (pending) |
| Support chat | 20 |
| Marriage chats | 51 and 52 |
| Staff chats | 61, and 62 (ended, archived) |
| Bodies with line breaks, commas and quotes | messages 7004 (donor chat 7), 5104 (marriage chat 51), 6103 (staff chat 61) |

### Check a conversation export by hand

1. Open **Messages**, **Marriage Chats** or **Staff Chat** and select the first conversation.
2. Press **Export conversation**, pick **CSV**, and type any password; the mock accepts every password.
3. Open the file. The columns are Message ID, Sent at, Sender name, Sender user ID, Sender role and Body. The last message's body sits in one cell, line breaks and all.

The donor and marriage pages load the conversation again after the password. The staff page reuses the messages it already shows, because the real staff messages route marks the thread read.

## Keep it honest

The mock is only useful while it matches the backend. When a handler's JSON changes:

1. Update the fixture type that names that handler.
2. Update the route: shell and chat groups live in `scripts/mock-api-routes.mjs`; lifecycle, delete and the older chats in `scripts/mock-api-chat-routes.mjs`.
3. Add a case to `scripts/mock-api.test.mjs`.

The test already fails when `backend/internal/permissions/permissions.go` gains a module or an action.

**The mock scripts have no ESLint coverage today.** `eslint.config.js` configures only `**/*.{ts,tsx}`, so `npm run lint` applies zero rules to `scripts/*.mjs`, this mock included (check with `npx eslint --print-config scripts/mock-api.mjs`). Until the lint follow-up (OPOS #26437) covers them, `npm run test:mock-api` is their only automated check.

Known differences from the real API:

- **Access.** No authentication, no per-user permissions and no sensitive-data masking: every reply is what a super_admin sees.
- **Contact-detail refusals.** Staff messages are never refused for contact details. The backend exempts staff (`handlers/chat_group_contact_block.go`), and the mock only ever acts as staff.
- **Masked labels.** A typed masked label is not scanned for contact details. The backend refuses such a label with 400 `group_label_contact` (`refuseContactInLabel` in `internal/chatgroups/chatgroups.go`).
- **Refusal codes.** The chat-group routes follow the final error contract that the backend branches in flight bring to `main`:
  - every refusal carries a `code`: `group_not_found` (including a missing group's messages and contact blocks), `group_invalid_input`, `group_member_conflict`, `group_label_conflict`, `guest_member_not_allowed` and `connect_request_decided`;
  - a missing connect request is a 404 with no code, as on the backend;
  - re-adding a removed member reactivates them with their old label and role (decision D3).

  Not mocked: `group_label_contact`, `sensitive_data_required`, `not_group_member`, `contact_details_blocked` and `server_error`. The dashboard translates all of them (`src/lib/chatGroupErrors.ts`).
- **Staff chats.** Messages are not limited to the two participants.
- **Validation.** The mock does not check that a user id exists.
