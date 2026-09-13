# OPOS #25284 Phase 3 — Connect-Request End-to-End

**Status:** Approved design, ready for implementation planning.
**Date:** 2026-09-13
**Depends on:** Phase 1 (PR #71, `internal/chatgroups` Store) and Phase 2 (PR #72, routes/permissions/lifecycle) — both unmerged as of this writing; this branch builds on top of Phase 2's tip.

## 1. Scope

Phase 1 shipped `SubmitConnectRequest`/`ApproveConnectRequest`/`DeclineConnectRequest`/
`ListConnectRequests` at the Store layer with no HTTP surface. Phase 3 exposes
them: a mobile route for a donor/beneficiary/volunteer to ask staff to open a
chat, and admin routes to triage, approve (creating the group transactionally),
or decline. This is the last piece of chat-groups' own backend surface —
after this phase, everything Phase 1's design spec promised is reachable over
HTTP.

Full flow already specified in
`docs/superpowers/specs/2026-09-12-masked-group-chats-design.md` §6, §7, §9,
§10 — this document only fills in the HTTP-layer specifics that spec left to
"a later phase," and fixes two Important gaps Phase 1/2's reviews already
identified in the Store methods this phase is the first real caller of.

## 2. Endpoints

**Mobile** (`authed` group; the submit route additionally `RequireNotGuest()`,
matching every other mobile write route in this codebase):

| Method | Path | Store call |
|---|---|---|
| POST | `/chat-groups/connect-requests` | `SubmitConnectRequest(requesterID, contextType, contextID, targetHint, message)` |
| GET | `/chat-groups/connect-requests/mine` | new `Store.ListConnectRequestsForUser(requesterID)` (§4) |

**Admin** (`admin` group, `perm("messages", <action>)`):

| Method | Path | Store call |
|---|---|---|
| GET | `/admin/chat-groups/connect-requests` | `ListConnectRequests(status)` — `?status=` query param, empty = all |
| GET | `/admin/chat-groups/connect-requests/:id` | new `Store.GetConnectRequest(id)` (§4) — single-request detail, with resolved context (§3) |
| POST | `/admin/chat-groups/connect-requests/:id/approve` | `ApproveConnectRequest(id, kind, memberTitle, staffID, members)` |
| POST | `/admin/chat-groups/connect-requests/:id/decline` | `DeclineConnectRequest(id, staffID, reason)` |

Error mapping via the existing `chatErr` dispatcher (`chat_group.go`, already
built): `ErrNotFound`→404, `ErrAlreadyDecided`→409, `ErrInvalidInput`→400.

## 3. Context resolution (spec §6's requirement)

The admin inbox must show staff a campaign title, case number, or donation
amount — never a bare `context_id`. This resolution happens in the HANDLER
layer (`chat_group_admin.go`), not the Store, matching spec §6's own framing
and keeping `internal/chatgroups` free of dependencies on `campaigns`/
`donations`/`beneficiary` packages it has no other reason to import:

```go
// resolveConnectContext turns a connect request's raw context_type/context_id
// into a human-readable label for the admin inbox — staff cannot make a
// privacy decision from "context_id: 4471" (spec §6).
func (h *ChatGroupHandler) resolveConnectContext(ctx context.Context, contextType string, contextID int64) string {
	switch contextType {
	case "donation":
		var amount float64
		var campaignTitle string
		_ = h.Pool.QueryRow(ctx, `
			SELECT d.amount, COALESCE(c.title, 'General fund')
			  FROM donations d LEFT JOIN campaigns c ON c.id = d.campaign_id
			 WHERE d.id = $1`, contextID).Scan(&amount, &campaignTitle)
		if campaignTitle != "" {
			return fmt.Sprintf("Donation of %.0f to %q", amount, campaignTitle)
		}
	case "case":
		var caseCode, title string
		_ = h.Pool.QueryRow(ctx, `SELECT case_code, public_title FROM beneficiary_cases WHERE id = $1`, contextID).
			Scan(&caseCode, &title)
		if caseCode != "" {
			return fmt.Sprintf("Case %s — %s", caseCode, title)
		}
	}
	return fmt.Sprintf("%s #%d", contextType, contextID)
}
```

Best-effort (errors discarded, matching this handler file's existing
`groupSenderLabel` pattern for a similar best-effort lookup) — a resolution
failure falls back to the raw id rather than breaking the whole inbox
listing.

## 4. Two small Store additions

- `func (s *Store) GetConnectRequest(ctx context.Context, id int64) (ConnectRequest, error)` — single-row read, `ErrNotFound`-wrapped on `pgx.ErrNoRows`, same shape as `GetGroup`. Needed for the admin detail route.
- `func (s *Store) ListConnectRequestsForUser(ctx context.Context, requesterID int64) ([]ConnectRequest, error)` — same query as `ListConnectRequests` but `WHERE requester_user_id = $1 ORDER BY created_at DESC`, no status filter (a requester should see all their own requests' history, not just pending ones).
- `ConnectRequest` gains JSON tags (currently has none, since Phase 1 never returned it over HTTP) — same treatment `Group` got in Phase 2's Task 3.

## 5. Two Important fixes to `ApproveConnectRequest`, now that it has a real caller

Both flagged by Phase 1's final review and explicitly deferred "until a real
caller needs it" (this phase):

- **No `kind` validation.** `CreateGroup` validates `kind` (wraps
  `ErrInvalidInput` since Phase 2's Task 3 fix); `ApproveConnectRequest`
  builds the same `INSERT INTO chat_group_threads` inline and skips that
  check, relying only on the database's own `CHECK (kind IN ('masked',
  'team'))` constraint — which fails with a raw Postgres constraint-violation
  error, not `ErrInvalidInput`, so the admin handler can't turn a bad `kind`
  into a clean 400. Fix: validate `kind` at the top of
  `ApproveConnectRequest`, identical to `CreateGroup`'s own check.
- **No check that the requester is among `members`.** Approving a request
  with a `members` list that omits the original requester creates a group
  the requester who ASKED for it can never see or use — defeating the whole
  point of "approved, group created, requester not in it" (spec's own
  "no dangling state" argument, §6, applies just as much to this). Fix:
  after loading the request's `requester_user_id` inside the existing `FOR
  UPDATE` transaction, assert it appears in `members` before calling
  `insertMembers`; return `ErrInvalidInput` if not.

## 6. Staff activity logging (spec §9)

"Group creation, membership changes, and label edits are logged via
`internal/staffactivity`." Phase 2's `AdminCreateGroup`/`AdminAddMember`/
`AdminRemoveMember` shipped without this (tracked as its own follow-up, OPOS
#25634, since those routes are already merged/PR'd). This phase's OWN new
group-creation path — approving a connect request — must not repeat that
miss: log via `internal/staffactivity` (reuse its existing call shape from
`internal/handlers/admin_detail.go`'s `sensitive_data` unmask logging, the
same precedent spec §9 points at) immediately after a successful approval.

## 7. Testing

Per spec §12 and this plan's own established pattern (Phase 2's identity-leak
test was the highest-priority test of that phase; this phase's equivalent is
the full lifecycle round trip):

1. Submit → list-as-admin → approve → the resulting group is immediately
   usable: post a message as the (now-member) requester, read it back. One
   test proving the whole chain, not just each endpoint in isolation.
2. Approve where `members` omits the requester → `ErrInvalidInput` (400),
   proving Fix 2 (§5) actually gates.
3. Approve with an invalid `kind` → `ErrInvalidInput` (400), proving Fix 1.
4. Decline → the requester's own `GET /chat-groups/connect-requests/mine`
   shows the decline reason.
5. Resubmitting while pending updates the existing row, not a duplicate
   (Store-layer behavior already tested in Phase 1; add one HTTP-level test
   confirming the route surfaces this correctly — same id returned twice).
6. `ListConnectRequests`/`GetConnectRequest` reveal real requester ids —
   staff-only, `perm("messages","view")`, no `sensitive_data` gate needed
   (unlike group messages/roster — a connect request's requester id is not
   masking anyone, since no group/label exists yet at that point).

## 8. Explicitly out of scope

- Phase 4's chat retirement (removing the old direct chat) — a separate
  phase, though this phase's `context_type='case'` support is what Phase 4's
  point 6 (moving case coordination to a staff-created masked group) will
  build on.
- Flutter/admin-web clients — Phases 5-6.
- OPOS #25634 (Phase 2's staffactivity gap) — its own ticket, not retrofitted
  here; this phase only ensures its OWN new code doesn't repeat the miss.
