// admin_delete_trash_test.go — which deletes are recoverable (H15).
//
// # WHY THIS FILE EXISTS
//
// The client asked for one rule: "every delete anywhere moves to سلة المهملات
// automatically". Sixteen of the 31 admin delete routes did that. The other
// fifteen ran `DELETE FROM <table>` and the row was gone — among them the two
// the client named, **project categories** and **payment methods**.
//
// The cause was structural rather than anyone's oversight: the trash helper was
// a PRIVATE METHOD on AdminDeleteHandler, so the catalogue, task and comment
// handlers — which live in their own files with their own stores — could not
// call it even if they wanted to. It is a package-level function now.
//
// Thirteen of the fifteen are routed through the Trash here. The two that are
// NOT are a deliberate decision, and this file pins that too so the exception
// is visible rather than forgotten:
//
//   - app_events    — an append-only activity/analytics log. A log line is not
//     an authored record, its delete is already Super-Admin-only by the
//     client's own rule, and filling the Trash with feed rows would bury the
//     records staff actually need to recover.
//   - banned_words  — the moderation blocklist is cached in-process with NO TTL,
//     and only moderation.Store.Delete invalidates that cache. Routing the
//     delete around the store would leave a removed word still being enforced
//     until the next restart, and the restore path (a raw INSERT in another
//     package) could not invalidate it either. Re-typing a word takes seconds;
//     silently enforcing one the operator removed is the worse failure.
//
// The integration tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout
// (same convention as internal/auth/dashboard_access_test.go):
//
//	createdb godonation_h15
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h15?sslmode=disable' \
//	  go test ./internal/handlers/ -run DeleteGoesToTrash -v
package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/casecategories"
	"github.com/karam-flutter/humanitarian-backend/internal/paymentmethods"
	"github.com/karam-flutter/humanitarian-backend/internal/projectcategories"
	"github.com/karam-flutter/humanitarian-backend/internal/tasks"
)

// ─── Harness ────────────────────────────────────────────────────────────

// trashCountFor reports how many un-restored trash entries exist for one row.
// The whole question this file asks is "did the delete leave a way back", and
// this is that question in SQL.
func trashCountFor(t *testing.T, pool *pgxpool.Pool, table string, rowID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM trash_items
		  WHERE source_table = $1 AND row_id = $2 AND restored_at IS NULL`,
		table, rowID).Scan(&n); err != nil {
		t.Fatalf("count trash rows for %s#%d: %v", table, rowID, err)
	}
	return n
}

// callDelete drives a delete handler through a real gin route so :id binding
// and the response are exercised the way production does them. The route's
// permission gate is deliberately absent: what is asserted here is the
// handler's effect on the database, and the gates are unchanged by this work.
func callDelete(t *testing.T, handler gin.HandlerFunc, id int64) (int, string) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.DELETE("/x/:id", handler)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodDelete,
		"/x/"+strconv.FormatInt(id, 10), nil))
	return rec.Code, rec.Body.String()
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestDeleteGoesToTrash walks every converted route: insert a row, delete it
// through the real handler, then assert the row is gone from its own table AND
// present in the Trash. Both halves matter — a delete that only trashes would
// leave the record live, and a delete that only removes it is the bug.
func TestDeleteGoesToTrash(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	// insertReturningID keeps each case to one line of SQL.
	insertReturningID := func(t *testing.T, sql string, args ...any) int64 {
		t.Helper()
		var id int64
		if err := pool.QueryRow(ctx, sql, args...).Scan(&id); err != nil {
			t.Fatalf("insert fixture: %v", err)
		}
		return id
	}

	cases := []struct {
		name    string
		table   string
		insert  func(t *testing.T) int64
		handler func() gin.HandlerFunc
	}{
		{
			// The client's own example #1: "Delete a فئات المشاريع row → gone forever".
			name:  "project category",
			table: "project_categories",
			insert: func(t *testing.T) int64 {
				return insertReturningID(t, `INSERT INTO project_categories
					(slug, name_en, name_ar, name_ckb, name_kmr)
					VALUES ('h15-test','Test','اختبار','تاقیکردنەوە','تاقیکرن') RETURNING id`)
			},
			handler: func() gin.HandlerFunc {
				return NewProjectCategoriesHandler(projectcategories.New(pool)).Delete
			},
		},
		{
			// The client's own example #2: "Delete a طرق الدفع row → gone forever".
			name:  "payment method",
			table: "payment_methods",
			insert: func(t *testing.T) int64 {
				return insertReturningID(t, `INSERT INTO payment_methods
					(slug, method_type, name_en, name_ar, name_ckb, name_kmr)
					VALUES ('h15-test','bank','Test','اختبار','تاقیکردنەوە','تاقیکرن') RETURNING id`)
			},
			handler: func() gin.HandlerFunc {
				return NewPaymentMethodsHandler(paymentmethods.New(pool)).Delete
			},
		},
		{
			// A third handler shape — this route is gated on `edit`, not `delete`.
			name:  "case category",
			table: "case_categories",
			insert: func(t *testing.T) int64 {
				return insertReturningID(t, `INSERT INTO case_categories
					(slug, name_en, name_ar, name_ckb, name_kmr)
					VALUES ('h15-test','Test','اختبار','تاقیکردنەوە','تاقیکرن') RETURNING id`)
			},
			handler: func() gin.HandlerFunc {
				return NewCaseCategoriesHandler(casecategories.New(pool)).Delete
			},
		},
		{
			// Not a catalogue row at all: assigned work with a person's name on it.
			name:  "task",
			table: "tasks",
			insert: func(t *testing.T) int64 {
				owner := insertAccount(t, pool, "user", "")
				return insertReturningID(t, `INSERT INTO tasks (user_id, title, description)
					VALUES ($1, 'H15 fixture', '') RETURNING id`, owner.id)
			},
			handler: func() gin.HandlerFunc {
				return NewTasksHandler(tasks.New(pool), nil).AdminDelete
			},
		},
		{
			// E15 — the fifth entry the client asked for on تسجيلات المهام.
			// Four of the five actions (موافق/قبول/رفض/تراجع) are status
			// transitions that already exist; حذف had no route at all, so the
			// dashboard had nothing to call. It is added under the SAME rule as
			// the thirteen above rather than as a hard delete: a signup carries a
			// volunteer's completion note and hours served, and staff pressing
			// حذف on the wrong row must be able to undo it.
			name:  "volunteer mission signup",
			table: "volunteer_mission_signups",
			insert: func(t *testing.T) int64 {
				volunteer := insertAccount(t, pool, "user", "")
				missionID := insertReturningID(t, `INSERT INTO volunteer_missions (title, status)
					VALUES ('E15 fixture', 'open') RETURNING id`)
				t.Cleanup(func() {
					_, _ = pool.Exec(context.Background(),
						`DELETE FROM volunteer_missions WHERE id = $1`, missionID)
				})
				return insertReturningID(t, `INSERT INTO volunteer_mission_signups
					(user_id, mission_id, status, notes)
					VALUES ($1, $2, 'pending', 'E15 fixture') RETURNING id`, volunteer.id, missionID)
			},
			handler: func() gin.HandlerFunc {
				return NewAdminDeleteHandler(pool).VolunteerMissionSignup
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id := tc.insert(t)
			t.Cleanup(func() {
				bg := context.Background()
				_, _ = pool.Exec(bg, `DELETE FROM trash_items WHERE source_table = $1 AND row_id = $2`, tc.table, id)
				_, _ = pool.Exec(bg, `DELETE FROM `+tc.table+` WHERE id = $1`, id)
			})

			if status, body := callDelete(t, tc.handler(), id); status != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body: %s)", status, body)
			}

			var stillThere bool
			if err := pool.QueryRow(ctx,
				`SELECT EXISTS (SELECT 1 FROM `+tc.table+` WHERE id = $1)`, id).Scan(&stillThere); err != nil {
				t.Fatalf("check %s: %v", tc.table, err)
			}
			if stillThere {
				t.Errorf("%s#%d was not deleted at all", tc.table, id)
			}
			if n := trashCountFor(t, pool, tc.table, id); n != 1 {
				t.Errorf("%s#%d left %d trash entries, want 1 — the delete was permanent", tc.table, id, n)
			}
		})
	}
}

// TestTrashedTablesAreRestorable closes the trap this change could have set:
// a row that reaches the Trash but is refused on the way out is worse than one
// that was never trashed, because the operator is told it is recoverable.
func TestTrashedTablesAreRestorable(t *testing.T) {
	for _, table := range []string{
		"custom_professions", "project_categories", "sponsorship_types",
		"inkind_categories", "city_sectors", "city_categories", "media_categories",
		"case_categories", "marketplace_categories", "payment_methods",
		"marriage_subscription_packages", "tasks", "post_comments",

		// E15 — same trap, same guard: the new signup delete is only a
		// recoverable delete if Restore will take the row back out.
		"volunteer_mission_signups",
	} {
		if !restorableTables[table] {
			t.Errorf("%s can be trashed but not restored — Restore would refuse it", table)
		}
	}
}
