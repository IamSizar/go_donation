// chatgroups_connect_context_test.go — OPOS #26351: SubmitConnectRequest
// refuses a request about a case or donation that does not exist, and
// accepts one about any case or donation that does.
//
// WHAT THIS PINS
// The app keeps "Ask our team to connect me" on every case (any status, the
// member's own or not) and on every donation row; the server refuses ONLY a
// context that is not there. So the accept tests below deliberately include
// a rejected case, a hidden case, a case not yet reviewed, and the
// requester's own case — each one guards that decision. A future status or
// ownership rule has to change these tests on purpose, not by accident.
//
// A row moved to the Trash is deleted from its source table (see
// handlers.trashRow), so it is exactly as unknown as one that never existed;
// moveToTrashForTest reproduces that move.
//
// Needs the same throwaway Postgres as chatgroups_test.go — see newTestPool.
package chatgroups

import (
	"context"
	"errors"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// neverExistingContextID is far beyond any id a test database's sequences
// hand out, so no beneficiary_cases or donations row can hold it.
const neverExistingContextID int64 = 9_000_000_000_000_000

// ─── Fixtures ────────────────────────────────────────────────────────────

// caseFixture describes the beneficiary_cases row makeTestCase inserts.
type caseFixture struct {
	// OwnerID is the case's user_id; 0 leaves the case without an owner.
	OwnerID int64
	// Status is verification_status; "" stores NULL (a case not yet reviewed).
	Status string
	// Visibility is public_visibility; "" stores 'code_only', the column's
	// own default.
	Visibility string
}

// testCaseCodeSeq numbers fixture case codes. case_code is UNIQUE and the
// handlers package inserts cases into the same database concurrently, so the
// code also carries a package prefix and a nanosecond timestamp.
var testCaseCodeSeq int64

// makeTestCase inserts a beneficiary_cases row as described by fixture and
// deletes it on cleanup (a no-op when the test already moved it to the Trash).
func makeTestCase(t *testing.T, pool *pgxpool.Pool, fixture caseFixture) int64 {
	t.Helper()
	code := fmt.Sprintf("CG-STORE-%d-%d", time.Now().UnixNano(), atomic.AddInt64(&testCaseCodeSeq, 1))
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO beneficiary_cases (user_id, case_code, public_title, verification_status, public_visibility)
		VALUES (NULLIF($1, 0), $2, 'connect-context fixture', NULLIF($3, ''), COALESCE(NULLIF($4, ''), 'code_only'))
		RETURNING id`,
		fixture.OwnerID, code, fixture.Status, fixture.Visibility,
	).Scan(&id); err != nil {
		t.Fatalf("insert test case: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_cases WHERE id = $1`, id)
	})
	return id
}

// makeTestDonation inserts a donations row made by donorID and deletes it on
// cleanup. donations.user_id is a RESTRICT foreign key to users, so call this
// after donorID's makeTestUser: cleanups run last-in first-out, and the
// donation has to go before its donor can.
func makeTestDonation(t *testing.T, pool *pgxpool.Pool, donorID int64) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO donations (user_id, message, amount, payment_method)
		VALUES ($1, 'connect-context fixture', '1000', 'cash')
		RETURNING id`,
		donorID,
	).Scan(&id); err != nil {
		t.Fatalf("insert test donation: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM donations WHERE id = $1`, id)
	})
	return id
}

// moveToTrashForTest moves one row to the Trash the way handlers.trashRow
// does — snapshot it into trash_items, then delete it from its source table —
// and removes the trash_items row on cleanup. table must be a literal from
// this file: it is interpolated into the SQL.
func moveToTrashForTest(t *testing.T, pool *pgxpool.Pool, table string, id int64) {
	t.Helper()
	ctx := context.Background()
	if _, err := pool.Exec(ctx,
		`INSERT INTO trash_items (source_table, row_id, payload)
		 SELECT $1::varchar, t.id, to_jsonb(t.*) FROM `+table+` t WHERE t.id = $2`,
		table, id,
	); err != nil {
		t.Fatalf("snapshot %s %d into the trash: %v", table, id, err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM `+table+` WHERE id = $1`, id); err != nil {
		t.Fatalf("delete trashed %s %d: %v", table, id, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM trash_items WHERE source_table = $1 AND row_id = $2`, table, id)
	})
}

// ─── Refused: the context does not exist ─────────────────────────────────

// TestSubmitConnectRequestRefusesUnknownContext: a case or donation id that
// names no row — never created, or moved to the Trash — is refused with
// ErrUnknownContext, and no request row is left for staff to triage.
func TestSubmitConnectRequestRefusesUnknownContext(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	member := makeTestUser(t, pool, "donor")

	// makeTestUser's id floor is recomputed from MAX(users.id), which falls
	// back once an earlier run against the same database has deleted its
	// users, so a user id can be reissued — and request rows are never
	// cleaned up. Only rows written after this point are this test's own.
	var lastRequestBefore int64
	if err := pool.QueryRow(ctx,
		`SELECT COALESCE(MAX(id), 0) FROM chat_group_connect_requests`,
	).Scan(&lastRequestBefore); err != nil {
		t.Fatalf("read last request id: %v", err)
	}

	trashedCase := makeTestCase(t, pool, caseFixture{Status: "approved"})
	moveToTrashForTest(t, pool, "beneficiary_cases", trashedCase)
	trashedDonation := makeTestDonation(t, pool, member)
	moveToTrashForTest(t, pool, "donations", trashedDonation)

	for _, tc := range []struct {
		name        string
		contextType string
		contextID   int64
	}{
		{"case that never existed", "case", neverExistingContextID},
		{"case moved to the Trash", "case", trashedCase},
		{"donation that never existed", "donation", neverExistingContextID},
		{"donation moved to the Trash", "donation", trashedDonation},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := s.SubmitConnectRequest(ctx, member, tc.contextType, tc.contextID, nil, "please connect me")
			if !errors.Is(err, ErrUnknownContext) {
				t.Fatalf("SubmitConnectRequest(%s %d) = %v, want errors.Is(err, ErrUnknownContext)",
					tc.contextType, tc.contextID, err)
			}
		})
	}

	var written int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM chat_group_connect_requests WHERE requester_user_id = $1 AND id > $2`,
		member, lastRequestBefore,
	).Scan(&written); err != nil {
		t.Fatalf("count requests: %v", err)
	}
	if written != 0 {
		t.Fatalf("%d request rows written for unknown contexts, want 0", written)
	}
}

// ─── Accepted: the context exists, whatever its state ────────────────────

// TestSubmitConnectRequestAcceptsAnyExistingCase pins the user's decision:
// existence is the only rule on a case. Every subtest is a case the app shows
// the button on, including ones a status, visibility or ownership rule would
// refuse.
func TestSubmitConnectRequestAcceptsAnyExistingCase(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	requester := makeTestUser(t, pool, "beneficiary")
	owner := makeTestUser(t, pool, "beneficiary")

	for _, tc := range []struct {
		name    string
		fixture caseFixture
	}{
		{"approved case", caseFixture{OwnerID: owner, Status: "approved"}},
		{"pending case", caseFixture{OwnerID: owner, Status: "pending"}},
		{"rejected case", caseFixture{OwnerID: owner, Status: "rejected"}},
		{"case not yet reviewed", caseFixture{OwnerID: owner}},
		{"hidden case", caseFixture{OwnerID: owner, Status: "approved", Visibility: "hidden"}},
		{"case with no owner", caseFixture{Status: "approved"}},
		{"the requester's own pending case", caseFixture{OwnerID: requester, Status: "pending"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			caseID := makeTestCase(t, pool, tc.fixture)

			requestID, err := s.SubmitConnectRequest(ctx, requester, "case", caseID, nil, "please connect me")
			if err != nil {
				t.Fatalf("SubmitConnectRequest(case %d) = %v, want it accepted", caseID, err)
			}
			got, err := s.GetConnectRequest(ctx, requestID)
			if err != nil {
				t.Fatalf("GetConnectRequest(%d): %v", requestID, err)
			}
			if got.ContextType != "case" || got.ContextID != caseID {
				t.Errorf("stored context = %s %d, want case %d", got.ContextType, got.ContextID, caseID)
			}
		})
	}
}

// TestSubmitConnectRequestAcceptsExistingDonation: a donation that exists is
// accepted whoever asks — the donor (My Donations), or someone else, which is
// the campaign owner's path from that campaign's donations list.
func TestSubmitConnectRequestAcceptsExistingDonation(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	donor := makeTestUser(t, pool, "donor")
	someoneElse := makeTestUser(t, pool, "beneficiary")
	donationID := makeTestDonation(t, pool, donor)

	for _, tc := range []struct {
		name        string
		requesterID int64
	}{
		{"the donor", donor},
		{"someone other than the donor", someoneElse},
	} {
		t.Run(tc.name, func(t *testing.T) {
			requestID, err := s.SubmitConnectRequest(ctx, tc.requesterID, "donation", donationID, nil, "please connect me")
			if err != nil {
				t.Fatalf("SubmitConnectRequest(donation %d) = %v, want it accepted", donationID, err)
			}
			got, err := s.GetConnectRequest(ctx, requestID)
			if err != nil {
				t.Fatalf("GetConnectRequest(%d): %v", requestID, err)
			}
			if got.ContextType != "donation" || got.ContextID != donationID {
				t.Errorf("stored context = %s %d, want donation %d", got.ContextType, got.ContextID, donationID)
			}
		})
	}
}
