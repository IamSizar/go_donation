// chatgroups_admin_names_test.go — the real names the admin dashboard needs
// (part of OPOS #26410): every roster member's name on AdminGetGroup, and the
// requester's name on the connect-request inbox reads.
//
// The store only LOADS these names, and only on the admin reads. GetGroup —
// which the member routes call on every poll for their membership check —
// loads none. Whether a caller may SEE a loaded name is decided in the HTTP
// layer (handlers/chat_group_admin.go): the roster sits behind the
// masked-group sensitive_data check, and the requester's name is copied into
// the response only for a caller who may view sensitive data (user decision
// D6). That is why ConnectRequest must never serialize the name on its own —
// pinned by TestConnectRequestNeverSerializesRequesterName.
//
// Needs the same throwaway Postgres as chatgroups_test.go — see newTestPool.
package chatgroups

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Fixtures ────────────────────────────────────────────────────────────

// addRosterTestProfile gives userID a user_profiles row named fullName, and
// deletes it on cleanup. makeTestUser creates no profile, which is also the
// "no name on file" case these tests need.
func addRosterTestProfile(t *testing.T, pool *pgxpool.Pool, userID int64, fullName string) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, $2, '', '')`,
		userID, fullName,
	); err != nil {
		t.Fatalf("insert profile for user %d: %v", userID, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM user_profiles WHERE user_id = $1`, userID)
	})
}

// createNamesTestGroup creates a masked group with members and deletes every
// row it wrote on cleanup.
func createNamesTestGroup(t *testing.T, pool *pgxpool.Pool, staffID int64, members []MemberInput) int64 {
	t.Helper()
	groupID, err := New(pool).CreateGroup(context.Background(), KindMasked, "", staffID, members)
	if err != nil {
		t.Fatalf("create group: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_audit_log WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, groupID)
	})
	return groupID
}

// submitNamesTestRequest files a connect request from requesterID about a
// fresh donation of theirs, and deletes the request on cleanup.
func submitNamesTestRequest(t *testing.T, pool *pgxpool.Pool, requesterID int64) int64 {
	t.Helper()
	donationID := makeTestDonation(t, pool, requesterID)
	id, err := New(pool).SubmitConnectRequest(context.Background(), requesterID, "donation", donationID, nil, "names test")
	if err != nil {
		t.Fatalf("submit connect request for user %d: %v", requesterID, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM chat_group_connect_requests WHERE id = $1`, id)
	})
	return id
}

// membersByUser indexes a roster by user id.
func membersByUser(members []GroupMember) map[int64]GroupMember {
	out := make(map[int64]GroupMember, len(members))
	for _, m := range members {
		out[m.UserID] = m
	}
	return out
}

// ─── Roster names ────────────────────────────────────────────────────────

// TestAdminGetGroupMembersCarryRealName: on the admin read, a member with a
// profile carries its full_name and a member with no profile carries nil, not
// an empty string, so the dashboard can tell "no name on file" apart from a
// blank name. GetGroup, the member routes' read, carries no name at all.
func TestAdminGetGroupMembersCarryRealName(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	named := makeTestUser(t, pool, "donor")
	addRosterTestProfile(t, pool, named, "Roster Store Real Name")
	unnamed := makeTestUser(t, pool, "beneficiary")
	groupID := createNamesTestGroup(t, pool, staff, []MemberInput{
		{UserID: named, RoleInGroup: "donor"},
		{UserID: unnamed, RoleInGroup: "beneficiary"},
	})

	t.Run("admin read carries names", func(t *testing.T) {
		detail, err := s.AdminGetGroup(ctx, groupID)
		if err != nil {
			t.Fatalf("admin get group: %v", err)
		}
		if len(detail.Members) != 2 {
			t.Fatalf("got %d roster rows, want 2", len(detail.Members))
		}
		byUser := membersByUser(detail.Members)
		if got := byUser[named].FullName; got == nil || *got != "Roster Store Real Name" {
			t.Fatalf("named member FullName = %v, want \"Roster Store Real Name\"", got)
		}
		if got := byUser[unnamed].FullName; got != nil {
			t.Fatalf("unnamed member FullName = %q, want nil", *got)
		}
	})

	t.Run("member read carries none", func(t *testing.T) {
		detail, err := s.GetGroup(ctx, groupID)
		if err != nil {
			t.Fatalf("get group: %v", err)
		}
		for _, m := range detail.Members {
			if m.FullName != nil {
				t.Fatalf("GetGroup loaded member %d's name %q; only AdminGetGroup may", m.UserID, *m.FullName)
			}
		}
	})
}

// TestAdminGetGroupRosterSurvivesDuplicateProfileRows: user_profiles.user_id
// carries no UNIQUE constraint, so a user can have two profile rows. The
// roster must still list that member once, named from the oldest row.
func TestAdminGetGroupRosterSurvivesDuplicateProfileRows(t *testing.T) {
	pool := newTestPool(t)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	addRosterTestProfile(t, pool, donor, "First Profile Name")
	addRosterTestProfile(t, pool, donor, "Second Profile Name")
	groupID := createNamesTestGroup(t, pool, staff, []MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	detail, err := New(pool).AdminGetGroup(context.Background(), groupID)

	if err != nil {
		t.Fatalf("admin get group: %v", err)
	}
	if len(detail.Members) != 1 {
		t.Fatalf("got %d roster rows, want 1 — a second profile row duplicated the member", len(detail.Members))
	}
	if got := detail.Members[0].FullName; got == nil || *got != "First Profile Name" {
		t.Fatalf("FullName = %v, want the oldest profile row's \"First Profile Name\"", got)
	}
}

// TestAdminGetGroupReturnsErrNotFoundForUnknownGroup: the admin read fails the
// same way GetGroup does, so the handler's 404 still applies.
func TestAdminGetGroupReturnsErrNotFoundForUnknownGroup(t *testing.T) {
	pool := newTestPool(t)

	_, err := New(pool).AdminGetGroup(context.Background(), 999999999)

	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("err = %v, want ErrNotFound", err)
	}
}

// ─── Requester names ─────────────────────────────────────────────────────

// TestConnectRequestAdminReadsCarryRequesterName: the inbox list — filtered or
// not — and the single-request read both carry the requester's profile name,
// and nil when the requester has no profile. A requester with two profile
// rows is still listed once.
func TestConnectRequestAdminReadsCarryRequesterName(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	named := makeTestUser(t, pool, "donor")
	addRosterTestProfile(t, pool, named, "Requester Store Real Name")
	addRosterTestProfile(t, pool, named, "Requester Second Profile")
	unnamed := makeTestUser(t, pool, "donor")
	namedRequest := submitNamesTestRequest(t, pool, named)
	unnamedRequest := submitNamesTestRequest(t, pool, unnamed)

	for _, status := range []string{"", "pending"} {
		t.Run("list status="+status, func(t *testing.T) {
			list, err := s.ListConnectRequests(ctx, status)
			if err != nil {
				t.Fatalf("list connect requests: %v", err)
			}
			byID := map[int64]ConnectRequest{}
			seen := map[int64]int{}
			for _, r := range list {
				byID[r.ID] = r
				seen[r.ID]++
			}
			if seen[namedRequest] != 1 {
				t.Fatalf("request %d listed %d times, want once", namedRequest, seen[namedRequest])
			}
			if got := byID[namedRequest].RequesterName; got == nil || *got != "Requester Store Real Name" {
				t.Fatalf("named request RequesterName = %v, want \"Requester Store Real Name\"", got)
			}
			if seen[unnamedRequest] != 1 {
				t.Fatalf("request %d listed %d times, want once", unnamedRequest, seen[unnamedRequest])
			}
			if got := byID[unnamedRequest].RequesterName; got != nil {
				t.Fatalf("unnamed request RequesterName = %q, want nil", *got)
			}
		})
	}

	t.Run("get", func(t *testing.T) {
		got, err := s.GetConnectRequest(ctx, namedRequest)
		if err != nil {
			t.Fatalf("get connect request: %v", err)
		}
		if got.RequesterName == nil || *got.RequesterName != "Requester Store Real Name" {
			t.Fatalf("RequesterName = %v, want \"Requester Store Real Name\"", got.RequesterName)
		}
		if got.RequesterID != named {
			t.Fatalf("RequesterID = %d, want %d", got.RequesterID, named)
		}
	})
}

// TestConnectRequestNeverSerializesRequesterName: the store type carries the
// name for the handler to decide on, and must never put it on the wire by
// itself — MyConnectRequests, or any future handler that serializes the store
// type directly, would otherwise hand it out unchecked.
func TestConnectRequestNeverSerializesRequesterName(t *testing.T) {
	name := "Serialized Requester Name"

	raw, err := json.Marshal(ConnectRequest{ID: 1, RequesterName: &name})

	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if strings.Contains(string(raw), "requester_name") || strings.Contains(string(raw), name) {
		t.Fatalf("ConnectRequest serialized the requester's name: %s", raw)
	}
}
