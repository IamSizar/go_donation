// F7 — قائمة المهام could not be reordered, because nothing stored an order.
//
// THE SHAPE OF THE GAP
// F7 asks for four things on Dashboard → المتطوعين → قائمة المهام: add, edit,
// change section, reorder. Add/edit/delete/status already worked. The last two
// could not be built at all: volunteer_missions (001_full_v2.sql:691-709) had
// no section column and no display_order, and none of migrations 002–105 added
// one. The list was hard-ordered `ORDER BY m.id DESC` with no way for staff to
// influence it. Migration 106 adds both columns; this file pins the reorder
// half, which is the piece with real failure modes.
//
// WHAT IS WORTH TESTING HERE
// Not "does UPDATE work" — that a single UPDATE runs is not interesting. What
// matters is (1) the whole reorder is atomic, so a half-applied order can
// never be observed, and (2) reordering does not disturb a mission's other
// columns, since the operator is dragging a row, not editing it.
//
// Needs a throwaway Postgres and is skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_f7          # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_f7?sslmode=disable' \
//	  go test ./internal/handlers/ -run MissionReorder -v
package handlers

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

func newMissionTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping mission-reorder integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// makeMissions inserts three missions and removes them afterwards, so the test
// never depends on — or disturbs — whatever else is in the table.
func makeMissions(t *testing.T, pool *pgxpool.Pool) []int64 {
	t.Helper()
	ctx := context.Background()
	ids := []int64{}
	for _, title := range []string{"F7 alpha", "F7 beta", "F7 gamma"} {
		var id int64
		if err := pool.QueryRow(ctx,
			`INSERT INTO volunteer_missions (title, status, city, section)
			 VALUES ($1, 'open', 'Erbil', 'Field work') RETURNING id`, title,
		).Scan(&id); err != nil {
			t.Fatalf("insert mission %q: %v", title, err)
		}
		ids = append(ids, id)
	}
	t.Cleanup(func() {
		for _, id := range ids {
			_, _ = pool.Exec(context.Background(), `DELETE FROM volunteer_missions WHERE id = $1`, id)
		}
	})
	return ids
}

func orderOf(t *testing.T, pool *pgxpool.Pool, id int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT display_order FROM volunteer_missions WHERE id = $1`, id).Scan(&n); err != nil {
		t.Fatalf("read display_order for %d: %v", id, err)
	}
	return n
}

// TestMissionReorderAppliesTheGivenSequence is the F7 row: the order staff pick
// is the order that is stored.
func TestMissionReorderAppliesTheGivenSequence(t *testing.T) {
	pool := newMissionTestPool(t)
	ids := makeMissions(t, pool)
	// Drag the last one to the front.
	want := []int64{ids[2], ids[0], ids[1]}

	if err := reorderMissions(context.Background(), pool, want); err != nil {
		t.Fatalf("reorderMissions: %v", err)
	}
	for i, id := range want {
		if got := orderOf(t, pool, id); got != i+1 {
			t.Errorf("mission %d is at position %d, want %d", id, got, i+1)
		}
	}
}

// TestMissionReorderIsAtomic pins the property that matters when it goes wrong.
// A reorder naming a mission that does not exist must leave every position as
// it was, rather than applying the first few and abandoning the rest — a
// half-applied order is worse than a refused one, because the operator sees a
// list that looks reordered and is not.
func TestMissionReorderIsAtomic(t *testing.T) {
	pool := newMissionTestPool(t)
	ids := makeMissions(t, pool)

	if err := reorderMissions(context.Background(), pool, ids); err != nil {
		t.Fatalf("baseline reorder: %v", err)
	}
	before := []int{orderOf(t, pool, ids[0]), orderOf(t, pool, ids[1]), orderOf(t, pool, ids[2])}

	// A stale browser tab sends an id that has since been deleted.
	err := reorderMissions(context.Background(), pool, []int64{ids[2], 9_000_000_001, ids[0]})
	if err == nil {
		t.Fatal("reorder naming an unknown mission succeeded; want an error")
	}
	after := []int{orderOf(t, pool, ids[0]), orderOf(t, pool, ids[1]), orderOf(t, pool, ids[2])}
	for i := range before {
		if before[i] != after[i] {
			t.Fatalf("a failed reorder still moved things: positions %v -> %v", before, after)
		}
	}
}

// TestMissionReorderTouchesOnlyThePosition — dragging a row must not edit it.
// The reorder statement writes one column; this proves it, because a broader
// UPDATE here would quietly blank fields the operator never opened.
func TestMissionReorderTouchesOnlyThePosition(t *testing.T) {
	pool := newMissionTestPool(t)
	ids := makeMissions(t, pool)
	ctx := context.Background()

	var titleBefore, statusBefore, sectionBefore string
	if err := pool.QueryRow(ctx,
		`SELECT title, status, section FROM volunteer_missions WHERE id = $1`, ids[0],
	).Scan(&titleBefore, &statusBefore, &sectionBefore); err != nil {
		t.Fatalf("read before: %v", err)
	}

	if err := reorderMissions(ctx, pool, []int64{ids[1], ids[2], ids[0]}); err != nil {
		t.Fatalf("reorderMissions: %v", err)
	}

	var titleAfter, statusAfter, sectionAfter string
	if err := pool.QueryRow(ctx,
		`SELECT title, status, section FROM volunteer_missions WHERE id = $1`, ids[0],
	).Scan(&titleAfter, &statusAfter, &sectionAfter); err != nil {
		t.Fatalf("read after: %v", err)
	}
	if titleAfter != titleBefore || statusAfter != statusBefore || sectionAfter != sectionBefore {
		t.Fatalf("reorder changed more than the position: (%q,%q,%q) -> (%q,%q,%q)",
			titleBefore, statusBefore, sectionBefore, titleAfter, statusAfter, sectionAfter)
	}
}
