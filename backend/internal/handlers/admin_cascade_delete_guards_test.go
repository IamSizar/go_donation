// Package handlers tests — the remaining three cascades onto trashRow, and
// the judgement each one got.
//
//	beneficiary_cases  ├─ case_volunteer_chat_threads → _messages, _reads
//	                   └─ beneficiary_case_documents
//	sponsorships       └─ sponsorship_schedule
//	beneficiary_project_requests
//	                   ├─ _comments
//	                   └─ _likes
//
// trashRow archives only the row it deletes, so every one of those children was
// destroyed and المهملات handed the parent back alone.
//
// The three are tested together because the interesting part is that they did
// NOT all get the same remedy, and the tests are what hold that apart:
//
//   - a case refuses on messages or documents — the same conversation ee50aae
//     protected on the signup route, reachable through a second door;
//
//   - a sponsorship refuses only on SETTLED occurrences, because
//     sponsorshipschedule.Generate rebuilds the unsettled ones from the
//     sponsorship's own recurrence rule;
//
//   - a project request refuses on comments and ignores likes.
//
//     TEST_DATABASE_URL='postgres://localhost:5432/godonation_h10?sslmode=disable' \
//     go test -p 1 ./internal/handlers/ -run 'CaseDelete|SponsorshipDelete|ProjectRequestDelete'
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── beneficiary_cases ──────────────────────────────────────────────────

// caseRecordsFixture is one case plus the conversation and evidence on it.
type caseRecordsFixture struct {
	caseID   int64
	threadID int64
}

// makeCaseWithRecords builds a case carrying `messages` volunteer-chat messages
// and `documents` uploaded files. The thread is always created — it is opened
// automatically when a signup is approved, so an empty one must not block.
func makeCaseWithRecords(t *testing.T, pool *pgxpool.Pool, messages, documents int) caseRecordsFixture {
	t.Helper()
	ctx := context.Background()

	beneficiary := insertAccount(t, pool, "user", "")
	volunteer := insertAccount(t, pool, "user", "")

	var caseID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_cases (user_id, case_code, public_title,
		                                verification_status, public_visibility)
		 VALUES ($1, $2, 'case delete guard fixture', 'approved', 'summary') RETURNING id`,
		beneficiary.id, fmt.Sprintf("CASE-GUARD-%d", beneficiary.id),
	).Scan(&caseID); err != nil {
		t.Fatalf("insert beneficiary case: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM trash_items WHERE source_table = 'beneficiary_cases' AND row_id = $1`, caseID)
		_, _ = pool.Exec(bg, `DELETE FROM beneficiary_cases WHERE id = $1`, caseID)
	})

	var missionID, signupID, threadID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_missions (title, status)
		 VALUES ('case delete guard fixture', 'open') RETURNING id`).Scan(&missionID); err != nil {
		t.Fatalf("insert mission: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM volunteer_missions WHERE id = $1`, missionID)
	})
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_mission_signups (user_id, mission_id, beneficiary_case_id, status)
		 VALUES ($1, $2, $3, 'approved') RETURNING id`, volunteer.id, missionID, caseID,
	).Scan(&signupID); err != nil {
		t.Fatalf("insert signup: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO case_volunteer_chat_threads (signup_id, case_id, volunteer_user_id, beneficiary_user_id)
		 VALUES ($1, $2, $3, $4) RETURNING id`, signupID, caseID, volunteer.id, beneficiary.id,
	).Scan(&threadID); err != nil {
		t.Fatalf("insert case-volunteer thread: %v", err)
	}
	for i := 0; i < messages; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO case_volunteer_chat_messages (thread_id, sender_user_id, sender_role, body)
			 VALUES ($1, $2, 'volunteer', 'message worth keeping')`, threadID, volunteer.id); err != nil {
			t.Fatalf("insert case-volunteer message: %v", err)
		}
	}
	for i := 0; i < documents; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO beneficiary_case_documents (case_id, document_type, file_path, uploaded_by_user_id)
			 VALUES ($1, 'id_card', '/uploads/guard-fixture.jpg', $2)`, caseID, beneficiary.id); err != nil {
			t.Fatalf("insert case document: %v", err)
		}
	}

	return caseRecordsFixture{caseID: caseID, threadID: threadID}
}

// TestCaseDeleteRefusesWhenItWouldDestroyRecords — the second door onto the
// conversation ee50aae protected, plus the evidence the case was verified on.
func TestCaseDeleteRefusesWhenItWouldDestroyRecords(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	f := makeCaseWithRecords(t, pool, 2, 1)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).BeneficiaryCase, f.caseID)

	if status != http.StatusConflict {
		t.Errorf("status = %d, want 409 — deleting the case must not walk around the signup guard (body: %s)", status, body)
	}
	var caseStillThere bool
	if err := pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM beneficiary_cases WHERE id = $1)`, f.caseID).Scan(&caseStillThere); err != nil {
		t.Fatalf("check case: %v", err)
	}
	if !caseStillThere {
		t.Error("the case was deleted despite the refusal")
	}
	if n := countCaseVolMessages(t, pool, f.threadID); n != 2 {
		t.Errorf("%d of 2 messages survived — the conversation was destroyed", n)
	}
	var docs int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM beneficiary_case_documents WHERE case_id = $1`, f.caseID).Scan(&docs); err != nil {
		t.Fatalf("count documents: %v", err)
	}
	if docs != 1 {
		t.Errorf("%d of 1 documents survived — the case's verification evidence was destroyed", docs)
	}
	if n := trashCountFor(t, pool, "beneficiary_cases", f.caseID); n != 0 {
		t.Errorf("%d trash entries for a refused delete, want 0", n)
	}
}

// TestCaseDeleteRefusalTellsTheOperatorWhy — actionable and localisable.
func TestCaseDeleteRefusalTellsTheOperatorWhy(t *testing.T) {
	pool := newAuthTestPool(t)

	f := makeCaseWithRecords(t, pool, 1, 2)

	_, body := callDelete(t, NewAdminDeleteHandler(pool).BeneficiaryCase, f.caseID)

	var resp struct {
		Success   bool   `json:"success"`
		Error     string `json:"error"`
		Code      string `json:"code"`
		Messages  int    `json:"messages"`
		Documents int    `json:"documents"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatalf("unmarshal refusal body %q: %v", body, err)
	}
	if resp.Code != "case_has_records" {
		t.Errorf("code = %q, want case_has_records", resp.Code)
	}
	if resp.Messages != 1 || resp.Documents != 2 {
		t.Errorf("messages/documents = %d/%d, want 1/2", resp.Messages, resp.Documents)
	}
	if resp.Error == "" {
		t.Error("no fallback message; a client without the code mapping would show nothing")
	}
}

// TestCaseDeleteStillWorksWithNothingToLose — the thread is opened on approval
// before anyone types, so an empty one must not make the case undeletable.
func TestCaseDeleteStillWorksWithNothingToLose(t *testing.T) {
	pool := newAuthTestPool(t)

	f := makeCaseWithRecords(t, pool, 0, 0)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).BeneficiaryCase, f.caseID)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — an empty thread and no documents leave nothing to protect (body: %s)", status, body)
	}
	if n := trashCountFor(t, pool, "beneficiary_cases", f.caseID); n != 1 {
		t.Errorf("%d trash entries, want 1 — the delete must stay recoverable", n)
	}
}

// ─── sponsorships ───────────────────────────────────────────────────────

// makeSponsorshipWithSchedule builds a sponsorship with `settled` paid dates
// and `upcoming` unsettled ones.
func makeSponsorshipWithSchedule(t *testing.T, pool *pgxpool.Pool, settled, upcoming int) int64 {
	t.Helper()
	ctx := context.Background()

	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO sponsorships (sponsorship_type, status, schedule_interval)
		 VALUES ('orphan', 'active', 'monthly') RETURNING id`).Scan(&id); err != nil {
		t.Fatalf("insert sponsorship: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM trash_items WHERE source_table = 'sponsorships' AND row_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM sponsorship_schedule WHERE sponsorship_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM sponsorships WHERE id = $1`, id)
	})

	// due_date is UNIQUE per sponsorship, so each row gets its own month.
	month := 1
	for i := 0; i < settled; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO sponsorship_schedule (sponsorship_id, due_date, amount, status, paid_at)
			 VALUES ($1, make_date(2026, $2, 1), 50000, 'paid', CURRENT_TIMESTAMP)`, id, month); err != nil {
			t.Fatalf("insert settled occurrence: %v", err)
		}
		month++
	}
	for i := 0; i < upcoming; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO sponsorship_schedule (sponsorship_id, due_date, amount, status)
			 VALUES ($1, make_date(2026, $2, 1), 50000, 'upcoming')`, id, month); err != nil {
			t.Fatalf("insert upcoming occurrence: %v", err)
		}
		month++
	}
	return id
}

// TestSponsorshipDeleteRefusesWhenSettledDatesWouldBeLost — a paid date is a
// decision somebody made about money, and Generate never writes one back.
func TestSponsorshipDeleteRefusesWhenSettledDatesWouldBeLost(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	id := makeSponsorshipWithSchedule(t, pool, 2, 3)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).Sponsorship, id)

	if status != http.StatusConflict {
		t.Errorf("status = %d, want 409 — settled payment dates must not be destroyed (body: %s)", status, body)
	}
	var settled int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM sponsorship_schedule
		  WHERE sponsorship_id = $1 AND status = 'paid'`, id).Scan(&settled); err != nil {
		t.Fatalf("count settled: %v", err)
	}
	if settled != 2 {
		t.Errorf("%d of 2 settled schedule dates survived — the payment history was destroyed", settled)
	}
	if n := trashCountFor(t, pool, "sponsorships", id); n != 0 {
		t.Errorf("%d trash entries for a refused delete, want 0", n)
	}

	var resp struct {
		Code    string `json:"code"`
		Settled int    `json:"settled_occurrences"`
		Error   string `json:"error"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatalf("unmarshal refusal body %q: %v", body, err)
	}
	if resp.Code != "sponsorship_has_settled_schedule" {
		t.Errorf("code = %q, want sponsorship_has_settled_schedule", resp.Code)
	}
	if resp.Settled != 2 {
		t.Errorf("settled_occurrences = %d, want 2", resp.Settled)
	}
	if resp.Error == "" {
		t.Error("no fallback message; a client without the code mapping would show nothing")
	}
}

// TestSponsorshipDeleteStillWorksWithOnlyUnsettledDates is the judgement this
// route rests on, and it is deliberately not the same judgement the others
// got: sponsorshipschedule.Generate materialises upcoming rows from the
// sponsorship's own recurrence rule and is idempotent, so an unsettled
// occurrence is a projection, not a record. Refusing on every schedule row
// would have blocked practically every active sponsorship and protected
// nothing.
func TestSponsorshipDeleteStillWorksWithOnlyUnsettledDates(t *testing.T) {
	pool := newAuthTestPool(t)

	id := makeSponsorshipWithSchedule(t, pool, 0, 4)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).Sponsorship, id)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — unsettled dates are regenerated by Generate (body: %s)", status, body)
	}
	if n := trashCountFor(t, pool, "sponsorships", id); n != 1 {
		t.Errorf("%d trash entries, want 1 — the delete must stay recoverable", n)
	}
}

// ─── beneficiary_project_requests ───────────────────────────────────────

// makeProjectRequestWith builds a request with `comments` live comments,
// `deletedComments` already-withdrawn ones, and `likes` likes.
func makeProjectRequestWith(t *testing.T, pool *pgxpool.Pool, comments, deletedComments, likes int) int64 {
	t.Helper()
	ctx := context.Background()

	owner := insertAccount(t, pool, "user", "")
	commenter := insertAccount(t, pool, "user", "")

	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_project_requests
		   (user_id, project_title, category, summary, description_long,
		    amount_needed, location, beneficiary_community_name)
		 VALUES ($1, 'project request guard fixture', 'general', 'summary', 'long',
		         100000, 'Mosul', 'community') RETURNING id`, owner.id,
	).Scan(&id); err != nil {
		t.Fatalf("insert project request: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM trash_items WHERE source_table = 'beneficiary_project_requests' AND row_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM beneficiary_project_requests WHERE id = $1`, id)
	})

	for i := 0; i < comments; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO beneficiary_project_request_comments (project_request_id, user_id, body, is_deleted)
			 VALUES ($1, $2, 'a comment somebody wrote', 0)`, id, commenter.id); err != nil {
			t.Fatalf("insert comment: %v", err)
		}
	}
	for i := 0; i < deletedComments; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO beneficiary_project_request_comments (project_request_id, user_id, body, is_deleted)
			 VALUES ($1, $2, 'a withdrawn comment', 1)`, id, commenter.id); err != nil {
			t.Fatalf("insert withdrawn comment: %v", err)
		}
	}
	if likes > 0 {
		// UNIQUE (project_request_id, user_id) — one like per person.
		if _, err := pool.Exec(ctx,
			`INSERT INTO beneficiary_project_request_likes (project_request_id, user_id)
			 VALUES ($1, $2)`, id, commenter.id); err != nil {
			t.Fatalf("insert like: %v", err)
		}
	}
	return id
}

// TestProjectRequestDeleteRefusesWhenCommentsWouldBeLost — the comments were
// written by other people on somebody else's request.
func TestProjectRequestDeleteRefusesWhenCommentsWouldBeLost(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	id := makeProjectRequestWith(t, pool, 2, 0, 0)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).ProjectRequest, id)

	if status != http.StatusConflict {
		t.Errorf("status = %d, want 409 — user-written comments must not be destroyed (body: %s)", status, body)
	}
	var live int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM beneficiary_project_request_comments
		  WHERE project_request_id = $1 AND is_deleted = 0`, id).Scan(&live); err != nil {
		t.Fatalf("count comments: %v", err)
	}
	if live != 2 {
		t.Errorf("%d of 2 comments survived — what people wrote was destroyed", live)
	}
	if n := trashCountFor(t, pool, "beneficiary_project_requests", id); n != 0 {
		t.Errorf("%d trash entries for a refused delete, want 0", n)
	}

	var resp struct {
		Code     string `json:"code"`
		Comments int    `json:"comments"`
		Error    string `json:"error"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatalf("unmarshal refusal body %q: %v", body, err)
	}
	if resp.Code != "project_request_has_comments" {
		t.Errorf("code = %q, want project_request_has_comments", resp.Code)
	}
	if resp.Comments != 2 {
		t.Errorf("comments = %d, want 2", resp.Comments)
	}
	if resp.Error == "" {
		t.Error("no fallback message; a client without the code mapping would show nothing")
	}
}

// TestProjectRequestDeleteIgnoresLikesAndWithdrawnComments pins the judgement,
// so nobody widens the guard later without arguing it: a like carries no
// authored content and can be made again, and a withdrawn comment is already
// out of view. Neither is worth making a request permanently undeletable over.
func TestProjectRequestDeleteIgnoresLikesAndWithdrawnComments(t *testing.T) {
	pool := newAuthTestPool(t)

	id := makeProjectRequestWith(t, pool, 0, 1, 1)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).ProjectRequest, id)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — likes and withdrawn comments must not block a delete (body: %s)", status, body)
	}
	if n := trashCountFor(t, pool, "beneficiary_project_requests", id); n != 1 {
		t.Errorf("%d trash entries, want 1 — the delete must stay recoverable", n)
	}
}
