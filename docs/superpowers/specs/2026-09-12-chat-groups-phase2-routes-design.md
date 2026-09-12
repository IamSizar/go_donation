# OPOS #25284 Phase 2 — Routes, Permissions, and Lifecycle Registration for Chat Groups

**Status:** Approved design, ready for implementation planning.
**Date:** 2026-09-12
**Depends on:** Phase 1 (PR [#71](https://github.com/IamSizar/go_donation/pull/71), `internal/chatgroups` schema + Store — unmerged as of this writing; Phase 2 builds on top of that branch, not `main`).

## 1. Scope

Phase 1 shipped a complete, tested Store layer for masked/team group chats
with **zero HTTP surface** — nothing in `internal/chatgroups` is reachable
from the app or dashboard. Phase 2 is the first phase that exposes it:

- HTTP routes (mobile + admin) over every Phase 1 Store method.
- Permission gating consistent with how every other chat system in this
  codebase is gated.
- Registering `chat_group_threads` with `internal/chatlifecycle`, so pause /
  resume / archive / export / delete work for chat groups the same way they
  already do for the other four chat systems.
- The one piece of write-path policy Phase 1 deliberately left to the HTTP
  layer: contact-info filtering on masked-group messages (this codebase's
  existing K19 rule, adapted — see §5).
- Notification integration, including a new alias-bearing template so a
  masked group's push notification never carries a real name.

**Explicitly out of scope**, per the Phase 1 design doc's own phasing
(`docs/superpowers/specs/2026-09-12-masked-group-chats-design.md` §13):
the connect-request submit/approve/decline HTTP endpoints (Phase 3), the
Flutter client (Phase 5), the admin-web client (Phase 6), and retiring the
old direct-chat surfaces this replaces (Phase 4). The connect-request Store
methods (`SubmitConnectRequest`/`ApproveConnectRequest`/`DeclineConnectRequest`/
`ListConnectRequests`) already exist from Phase 1 but get no route in this
phase.

## 2. Current state (audited before designing this phase)

Every existing chat-adjacent handler (`internal/handlers/chat.go`,
`marriage_chat.go`, `case_volunteer_chat.go`, `staff_chat.go`) follows one
shape: a handler struct holding `Store`/`Notifier`/`Perms`, `auth.UserFromGin(c)`
for the acting user, `gin.H{"success": ...}` JSON envelopes, and a
per-handler `chatErr(c, err)` dispatcher using `errors.Is` against the
store's own sentinel errors. Routes are registered as flat blocks in
`cmd/server/main.go` on two groups: `authed` (bearer + approved) for mobile,
`admin` (`RequireAdmin` + per-route `perm(module, action)`) for the
dashboard. `internal/chatlifecycle` already treats "registering a chat
type" as a pure code change — one `Kind` constant plus one `systems` map
entry — after which the *existing*, fully generic `ChatLifecycleHandler`
(`internal/handlers/admin_chat_lifecycle.go`) serves pause/resume/archive/
delete/export for that type with no new handler code. `chatgroups`'s own
sentinel errors (`ErrNotMember`, `ErrNotFound`, `ErrAlreadyDecided`,
`ErrInvalidInput`, added in Phase 1's final review) already map cleanly onto
this codebase's 403/404/409/400 convention.

Contact-info filtering exists today only for the donor↔owner chat
(`internal/handlers/chat_contact_block.go`), gated by two exemptions: sender
is staff, or the thread has a staff party at all. The second exemption
cannot be reused for chat groups — a masked group always includes a staff
member, so reusing it verbatim would silently disable filtering for every
message a masked group ever carries. Delivery everywhere in this codebase
is plain HTTP polling (confirmed: no websockets/SSE anywhere in the stack);
`chatgroups.ListMessagesForMember`/`AdminListMessages` are already
cursor-paginated (`afterID`, `limit`, capped at 100) — no existing route
polling convention (`?after_id=`/`?since=`) needs matching since this is a
new resource; the Go parameter names are used directly as query params.

## 3. Architecture

One new handler area, following the existing pattern exactly rather than
introducing a new one:

- **`internal/handlers/chat_group.go`** — mobile-facing: `ChatGroupHandler`
  struct (`Store *chatgroups.Store`, `Notifier *notify.Notifier`, `Perms
  *permissions.Store`), `List`, `Messages`, `PostMessage`, `MarkRead`, and
  the shared `chatErr` dispatcher.
- **`internal/handlers/chat_group_admin.go`** — admin-facing methods on the
  same struct: `AdminList`, `AdminCreateGroup`, `AdminAddMember`,
  `AdminRemoveMember`, `AdminMessages`, `AdminPostMessage`. Split from the
  mobile file from the start rather than waiting for it to grow past the
  cap — `chat.go`'s equivalent single-file version is already 577 lines
  (over this codebase's own 500-line limit) with *fewer* distinct
  operations than chat groups needs (no group-creation or membership
  management exists in the `chat` package), so a from-the-start split here
  is the better call, matching Phase 1's own file-size discipline.
- **`internal/handlers/chat_group_contact_block.go`** — new file, adapting
  `chat_contact_block.go`'s rule for groups (§5).
- **Two small, additive Store methods** on `internal/chatgroups.Store` (same
  package, same test conventions as Phase 1 — not a reopening of reviewed
  Phase 1 code): `RecordContactBlock`/`ListContactBlocks` against the
  already-existing `chat_group_contact_blocks` table (mirrors
  `internal/chat/contactblocks.go`), and `LabelsForActiveMembers(ctx,
  groupID) (map[int64]string, error)` so notification fan-out resolves
  every recipient's alias or real name in one query instead of one per
  recipient. A `GetGroup`-style read (id, kind, title, members with their
  labels/roles) is also added here for the admin membership-management UI
  to have something to render before/after an `AddMember`/`RemoveMember`
  call.
- **`internal/notify/templates.go`**: one new template,
  `GroupMaskedNewMessageMsg(alias, preview string, groupID int64)
  LocalizedMessage` — same shape as the existing `ChatNewMessageMsg` but
  titled with the alias, `RelatedEntityType: "chat_group_thread"`. Team-kind
  groups reuse `ChatNewMessageMsg` with the real sender name directly — no
  new template needed there.
- **`internal/chatlifecycle/chatlifecycle.go`**: add `KindGroup` constant +
  one `systems` map entry (`ThreadTable: "chat_group_threads"`,
  `MessageTable: "chat_group_messages"`, `ReadTable: "chat_group_reads"`,
  `ExtraChildTables: []string{"chat_group_contact_blocks",
  "chat_group_staff_notes"}}`) — also wires trash/restore/export for free,
  since those already loop generically over `chatlifecycle.Systems()`.
- **`cmd/server/main.go`**: the route blocks in §4, plus two lifecycle
  lines (`chatLifecycleH.Apply(chatlifecycle.KindGroup)` /
  `.Delete(chatlifecycle.KindGroup)`), following the existing per-kind
  pattern verbatim.

## 4. Endpoints

**Mobile** (`authed` group: `auth.RequireBearer` + `RequireApproved()`;
write routes additionally `auth.RequireNotGuest()`, matching every existing
mobile chat route):

| Method | Path | Store call |
|---|---|---|
| GET | `/chat-groups` | `ListGroupsForUser(userID)` |
| GET | `/chat-groups/:id/messages?after_id=&limit=` | `ListMessagesForMember(id, userID, afterID, limit)` |
| POST | `/chat-groups/:id/messages` | contact-block gate (§5) → `PostMessage(id, userID, body)` → notify fan-out (§6) |
| POST | `/chat-groups/:id/read` | `MarkRead(id, userID, lastReadMsgID)`, body `{"last_read_msg_id": n}` |

**Admin** (`admin` group: `auth.RequireAdmin(tokenStore)`; each route also
`perm("messages", <action>)`):

| Method | Path | Store call | Extra gate |
|---|---|---|---|
| GET | `/admin/chat-groups` | `ListGroupsForStaff()` | `perm("messages","view")` |
| POST | `/admin/chat-groups` | `CreateGroup(kind, memberTitle, staffID, members)` | `perm("messages","add")` |
| GET | `/admin/chat-groups/:id` | `GetGroup(id)` (new, §3) | `perm("messages","view")` |
| POST | `/admin/chat-groups/:id/members` | `AddMember(id, input, staffID)` | `perm("messages","edit")` |
| DELETE | `/admin/chat-groups/:id/members/:userId` | `RemoveMember(id, userID, staffID)` | `perm("messages","edit")` |
| GET | `/admin/chat-groups/:id/messages?after_id=&limit=` | `AdminListMessages(id, afterID, limit)` | `perm("messages","view")` **+** `perm("sensitive_data","view")` — reveals real names/ids |
| POST | `/admin/chat-groups/:id/messages` | contact-block gate → `PostMessageAsStaff(id, staffID, body)` → notify fan-out | `perm("messages","add")` |
| GET | `/admin/chat-groups/:id/contact-blocks` | `ListContactBlocks(id)` | `perm("messages","view")` |
| POST | `/admin/chat-groups/:id/lifecycle` | generic `chatLifecycleH.Apply(KindGroup)` | `perm("messages","edit")` |
| DELETE | `/admin/chat-groups/:id` | generic `chatLifecycleH.Delete(KindGroup)` | `perm("messages","delete")` |

The `sensitive_data` module already exists in `internal/permissions`
(`Modules`, defaulting to admin-tier-only), used today by
`admin_contact_view.go`'s `canViewContact` for the same "otherwise-masked
data" reason — reused here rather than inventing a new gate.

Error mapping (`chatErr`, same dispatcher shape as `chat.go:416`):
`chatgroups.ErrNotMember`→403, `ErrNotFound`→404, `ErrAlreadyDecided`→409,
`ErrInvalidInput`→400, anything else→500 with the technical detail logged,
not returned.

## 5. Contact-info filtering on masked-group messages

Adapts this codebase's existing K19 rule (`chat_contact_block.go`) rather
than reusing its exemption logic verbatim, because one of the two existing
exemptions is wrong for groups:

- **Filter runs only when `group.kind == 'masked'`.** Team groups already
  show real names to every member — there is no masking invariant left to
  protect, so no filter runs there.
- **Within a masked group, the sender-is-staff exemption still applies** —
  a staff member relaying a real contact deliberately is the mediator
  working as designed, identical rationale to the existing rule.
- **The old "thread has a staff party → skip entirely" exemption is
  dropped.** A masked group always includes staff by construction, so
  keeping that exemption would silently disable filtering for every
  message any masked group ever carries — exactly the gap this phase must
  not reintroduce.
- A blocked message is refused (422, `contact_blocked_details` code, same
  bilingual copy pattern), never silently stripped — for the same reason
  the original K19 comment gives: a stripped message looks delivered, the
  push preview would already have leaked the number regardless, and refusal
  is the only point that actually holds.
- Every blocked attempt is recorded via the new `RecordContactBlock` Store
  method (mirrors `RecordContactBlock`/`ListContactBlocks` in
  `internal/chat/contactblocks.go`) against the already-existing
  `chat_group_contact_blocks` table from Phase 1's migration.

## 6. Notifications

`PostMessage`/`PostMessageAsStaff` call `LabelsForActiveMembers(groupID)`
once per post (not once per recipient — batching this was an explicit
requirement of the Phase 1 design doc), then fan out via the existing
detached-goroutine pattern (`go func(){ Notifier.Send(...) }()`,
10-second timeout context, identical to `chat.go`'s `bg()` helper) to every
active member except the sender:

- Masked groups → `GroupMaskedNewMessageMsg(alias, preview, groupID)`,
  where `alias` is that recipient's own view of the sender (their
  `masked_label`, or "Support" if the sender is staff — same resolution
  `ListMessagesForMember` already does at read time, reused here rather
  than re-derived).
- Team groups → the existing `ChatNewMessageMsg(realName, preview,
  groupID)`, no new template needed.

## 7. Testing

Per this codebase's `TEST_DATABASE_URL`-gated integration-test convention
(`internal/*_test.go` files that spin up a real Postgres schema), and the
Phase 1 design doc's own priority order (§12):

1. **The identity-leak HTTP test, highest priority.** Seed a masked group,
   hit `GET /chat-groups/:id/messages` as a non-staff member, and assert
   the **raw response body string** — not just the typed JSON fields —
   contains neither the real name, phone number, nor numeric user id of any
   other participant. This is the HTTP-layer proof that Phase 1's
   structural guarantee (no field in `GroupMessage` can hold that data)
   survives the trip through `gin.Context.JSON`.
2. One handler-level test per route: happy path, the relevant `chatErr`
   mapping (403 for `ErrNotMember`, etc.), 401 unauthenticated, 403 for a
   non-staff token hitting an admin route.
3. Contact-block filter: phone-shaped body from a non-staff sender in a
   masked group → 422 + a recorded block row; the same body from a staff
   sender → allowed; the same body in a team group → allowed (filter never
   runs).
4. Notification dispatch: assert a masked-group post enqueues
   `GroupMaskedNewMessageMsg` (never `ChatNewMessageMsg`) and a team-group
   post enqueues the reverse — via whatever fake/spy `Notifier` the
   existing `chat.go` tests already use for the same assertion shape.
5. `chatlifecycle.KindGroup` registration: extend the existing test(s) that
   already enumerate `chatlifecycle.Systems()` by name (flagged as a
   registration touchpoint in the Phase 1 design doc §8) rather than
   writing a parallel one.

## 8. Explicitly out of scope

- Connect-request HTTP endpoints (submit/approve/decline/list) — Phase 3.
- `moderation.ScanContact` over staff-typed masked *labels* — tracked as
  its own ticket, OPOS #25544. Not a task in this phase's plan; picked up
  as a separate, dedicated piece of work once this phase's
  `AdminCreateGroup`/`AdminAddMember` routes are live and are the first
  real place a label reaches the network.
- Retiring the old direct-chat surfaces (`chat` package's donor↔owner
  direct mode, `casevolchat`'s direct mode) — Phase 4. Both keep operating
  unchanged until then; Phase 2 adds a new, parallel surface only.
- Flutter and admin-web clients — Phases 5 and 6.
- The parked Phase 1 findings already logged in that phase's own ledger
  (group-listing order-by-last-activity, `ApproveConnectRequest`'s
  requester/kind validation, `ListConnectRequests` renaming, re-add-after-
  remove) — these belong to Phase 3, since they're all on the
  connect-request/group-listing surface that phase actually exposes.
