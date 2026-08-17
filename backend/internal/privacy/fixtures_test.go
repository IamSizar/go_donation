// Fixtures for the K8 enforcement tests (enforcement_test.go).
//
// Every helper writes the minimum a real serving query needs to return the
// row, and registers its own cleanup, so the tables are left exactly as found
// and the tests can run repeatedly against the same database.
package privacy_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/beneficiary"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
)

// ─── Donor ↔ owner chat ─────────────────────────────────────────────────

// openThread creates an active thread between two users and one message from
// each, so both the thread list and the message list have something to serve.
// Returns the thread id.
func openThread(t *testing.T, pool *pgxpool.Pool, donor, owner int64) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by)
		 VALUES ($1, $2, 'active', $1) RETURNING id`, donor, owner,
	).Scan(&id); err != nil {
		t.Fatalf("insert chat thread: %v", err)
	}
	for _, sender := range []int64{donor, owner} {
		if _, err := pool.Exec(ctx,
			`INSERT INTO chat_messages (thread_id, sender_user_id, body) VALUES ($1, $2, 'hello')`,
			id, sender); err != nil {
			t.Fatalf("insert chat message: %v", err)
		}
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM chat_messages WHERE thread_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM chat_threads WHERE id = $1`, id)
	})
	return id
}

// threadIDBetween finds the thread the fixture opened for this pair.
func threadIDBetween(t *testing.T, pool *pgxpool.Pool, donor, owner int64) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`SELECT id FROM chat_threads WHERE donor_user_id = $1 AND owner_user_id = $2`,
		donor, owner).Scan(&id); err != nil {
		t.Fatalf("find thread: %v", err)
	}
	return id
}

// findThread picks the view whose counterpart is the given user, failing the
// test rather than returning a zero value that would produce a confusing
// assertion failure later.
func findThread(t *testing.T, views []chat.ThreadView, otherID int64) chat.ThreadView {
	t.Helper()
	for _, v := range views {
		if v.OtherUserID == otherID {
			return v
		}
	}
	t.Fatalf("fixture problem: no thread with counterpart %d in %d views", otherID, len(views))
	return chat.ThreadView{}
}

// ─── Beneficiary cases ──────────────────────────────────────────────────

// makeCase writes an approved, publicly visible case owned by ownerID, with
// the personal columns the public listing serves populated.
func makeCase(t *testing.T, pool *pgxpool.Pool, ownerID int64) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_cases
		   (user_id, case_code, public_title, full_name, phone, address, city,
		    verification_status, public_visibility)
		 VALUES ($1, $2, 'Test case', 'Case Owner',
		         '9647999999999', 'Domiz Block 4', 'Kirkuk', 'approved', 'summary')
		 RETURNING id`, ownerID, fmt.Sprintf("K8-TEST-%d", ownerID),
	).Scan(&id); err != nil {
		t.Fatalf("insert beneficiary case: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_cases WHERE id = $1`, id)
	})
	return id
}

// makeOwnerlessCase inserts an approved, publicly visible case with user_id
// NULL — the row shape production is actually serving. beneficiary_cases.user_id
// has always been nullable (migration 001): a case can be entered by staff on
// behalf of someone who has no account in the app at all.
//
// It carries the same contact details as makeCase so a test can assert that the
// ONLY difference in what is published is the absence of an owner.
func makeOwnerlessCase(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	seq++
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_cases
		   (user_id, case_code, public_title, full_name, phone, address, city,
		    verification_status, public_visibility)
		 VALUES (NULL, $1, 'Ownerless test case', 'Nobody Consented',
		         '9647998888888', 'Domiz Block 9', 'Kirkuk', 'approved', 'summary')
		 RETURNING id`, fmt.Sprintf("K8-ORPHAN-%d-%d", runTag, seq),
	).Scan(&id); err != nil {
		t.Fatalf("insert ownerless beneficiary case: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_cases WHERE id = $1`, id)
	})
	return id
}

func findCase(t *testing.T, items []beneficiary.Case, caseID int64) beneficiary.Case {
	t.Helper()
	for _, c := range items {
		if c.ID == caseID {
			return c
		}
	}
	t.Fatalf("fixture problem: case %d not in the %d returned cases", caseID, len(items))
	return beneficiary.Case{}
}

// ─── Sponsorships ───────────────────────────────────────────────────────

func makeSponsorship(t *testing.T, pool *pgxpool.Pool, donorID int64) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO sponsorships (donor_user_id, sponsorship_type, amount, status)
		 VALUES ($1, 'monthly_support', 50000, 'active') RETURNING id`, donorID,
	).Scan(&id); err != nil {
		t.Fatalf("insert sponsorship: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM sponsorships WHERE id = $1`, id)
	})
	return id
}

// ─── Media posts and comments ───────────────────────────────────────────

func makePost(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO media_posts (title) VALUES ('K8 test post') RETURNING id`,
	).Scan(&id); err != nil {
		t.Fatalf("insert media post: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM media_posts WHERE id = $1`, id)
	})
	return id
}

// makeComment writes an APPROVED comment — the mobile feed only serves those.
func makeComment(t *testing.T, pool *pgxpool.Pool, postID, userID int64) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO post_comments (post_id, user_id, body, status)
		 VALUES ($1, $2, 'nice work', 'approved') RETURNING id`, postID, userID,
	).Scan(&id); err != nil {
		t.Fatalf("insert comment: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM post_comments WHERE id = $1`, id)
	})
	return id
}

// ─── Case ↔ volunteer chat ──────────────────────────────────────────────

// makeCaseVolThread builds the whole chain the thread's foreign keys need:
// a mission, the volunteer's signup on it, and a case owned by the
// beneficiary.
func makeCaseVolThread(t *testing.T, pool *pgxpool.Pool, volunteerID, beneficiaryID int64) int64 {
	t.Helper()
	ctx := context.Background()

	var missionID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_missions (title) VALUES ('K8 test mission') RETURNING id`,
	).Scan(&missionID); err != nil {
		t.Fatalf("insert mission: %v", err)
	}
	var signupID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_mission_signups (user_id, mission_id) VALUES ($1, $2) RETURNING id`,
		volunteerID, missionID,
	).Scan(&signupID); err != nil {
		t.Fatalf("insert signup: %v", err)
	}
	caseID := makeCase(t, pool, beneficiaryID)

	var threadID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO case_volunteer_chat_threads
		   (signup_id, case_id, volunteer_user_id, beneficiary_user_id)
		 VALUES ($1, $2, $3, $4) RETURNING id`,
		signupID, caseID, volunteerID, beneficiaryID,
	).Scan(&threadID); err != nil {
		t.Fatalf("insert case-volunteer thread: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM case_volunteer_chat_threads WHERE id = $1`, threadID)
		_, _ = pool.Exec(bg, `DELETE FROM volunteer_mission_signups WHERE id = $1`, signupID)
		_, _ = pool.Exec(bg, `DELETE FROM volunteer_missions WHERE id = $1`, missionID)
	})
	return threadID
}
