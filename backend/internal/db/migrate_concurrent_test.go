// migrate_concurrent_test.go — RunMigrations must survive several callers
// bringing the same database up at the same time.
//
// WHY THIS FILE EXISTS (finding 10)
//
// A dozen test packages call db.RunMigrations from their own harness, and
// `go test ./...` runs packages in parallel *as separate processes*. Against a
// fresh database they all saw an empty schema_migrations table, so they all
// applied the same files and raced, failing intermittently with either
//
//	record 010_phone_canonical.sql: duplicate key value violates unique
//	  constraint "schema_migrations_pkey"          (two callers recorded it)
//	apply 012_chat.sql: duplicate key value violates unique constraint
//	  "pg_type_typname_nsp_index"                  (two callers ran CREATE TYPE)
//
// The same race hits two server replicas booting with RUN_MIGRATIONS=1.
// RunMigrations now takes a session-level Postgres advisory lock around the
// whole read-apply-record loop, which serialises callers *across processes* —
// a sync.Once could never do that.
//
// The test drives concurrent callers through their own pools (one pool per
// caller = one session per caller, exactly like separate processes) over a
// throwaway set of migrations in a temp dir, so it reproduces the race in
// milliseconds without needing a freshly created database. It is skipped
// unless TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare
// checkout:
//
//	createdb godonation_test
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_test?sslmode=disable' \
//	  go test ./internal/db/ -run Concurrent -v
package db

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// probeVersionPrefix namespaces every artefact this test creates. It sorts
// after the real migrations and makes cleanup a single LIKE pattern.
const probeVersionPrefix = "zzz_migrate_race_"

// ─── Test ───────────────────────────────────────────────────────────────

// TestRunMigrationsIsSafeUnderConcurrentCallers is the regression guard for the
// cross-process migration race: every caller must return successfully, and each
// migration must be applied and recorded exactly once no matter who won.
func TestRunMigrationsIsSafeUnderConcurrentCallers(t *testing.T) {
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping concurrent migration test")
	}
	ctx := context.Background()
	dir := writeProbeMigrations(t)

	// One pool per caller: pgx pools do not share connections, and the advisory
	// lock is scoped to a *session*, so this mirrors separate processes.
	const callers = 6
	pools := make([]*pgxpool.Pool, callers)
	for i := range pools {
		pool, err := pgxpool.New(ctx, url)
		if err != nil {
			t.Fatalf("connect test database: %v", err)
		}
		pools[i] = pool
		t.Cleanup(pool.Close)
	}
	// Registered after the pool closes so it runs *before* them (t.Cleanup is
	// LIFO) and still has a live connection to drop the probe artefacts.
	t.Cleanup(func() { dropProbeArtefacts(ctx, t, pools[0]) })

	// Release every caller from the same starting line to widen the race.
	start := make(chan struct{})
	errs := make([]error, callers)
	var wg sync.WaitGroup
	for i := range pools {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			errs[i] = RunMigrations(ctx, pools[i], dir)
		}(i)
	}
	close(start)
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Errorf("caller %d: RunMigrations: %v", i, err)
		}
	}

	// Recorded exactly once each: a second INSERT would have failed above, but
	// this also catches a caller that silently skipped the recording step.
	var recorded int
	if err := pools[0].QueryRow(ctx,
		`SELECT count(*) FROM schema_migrations WHERE version LIKE $1`,
		probeVersionPrefix+"%").Scan(&recorded); err != nil {
		t.Fatalf("count recorded probe migrations: %v", err)
	}
	if recorded != len(probeMigrations) {
		t.Errorf("recorded %d probe migrations, want %d", recorded, len(probeMigrations))
	}

	// Applied exactly once each: the table and the enum type only exist if the
	// winning caller actually ran the SQL, and CREATE would have failed if a
	// loser had run it too.
	var tableExists, typeExists bool
	if err := pools[0].QueryRow(ctx,
		`SELECT to_regclass($1) IS NOT NULL, to_regtype($2) IS NOT NULL`,
		probeVersionPrefix+"table", probeVersionPrefix+"mood").
		Scan(&tableExists, &typeExists); err != nil {
		t.Fatalf("look up probe objects: %v", err)
	}
	if !tableExists || !typeExists {
		t.Errorf("probe objects missing: table=%v type=%v", tableExists, typeExists)
	}
}

// ─── Harness ────────────────────────────────────────────────────────────

// probeMigrations is a throwaway migration set shaped like the real ones: a
// CREATE TABLE and a CREATE TYPE, the two statements that produced the observed
// duplicate-key errors when two callers ran them at once.
//
// The pg_sleep in the first file is deliberate. It holds the winning caller
// inside the apply step long enough for the others to read an empty
// schema_migrations and pile in, which is what makes an unserialised
// RunMigrations fail here every time instead of once in a while.
var probeMigrations = []struct{ name, sql string }{
	{probeVersionPrefix + "001.sql",
		`CREATE TABLE ` + probeVersionPrefix + `table (id INT PRIMARY KEY);
		 SELECT pg_sleep(0.2);`},
	{probeVersionPrefix + "002.sql",
		`CREATE TYPE ` + probeVersionPrefix + `mood AS ENUM ('calm', 'racy');`},
	{probeVersionPrefix + "003.sql",
		`ALTER TABLE ` + probeVersionPrefix + `table ADD COLUMN mood ` +
			probeVersionPrefix + `mood;`},
}

// writeProbeMigrations lays probeMigrations out in a temp dir and returns its
// path. t.TempDir removes it when the test ends.
func writeProbeMigrations(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	for _, m := range probeMigrations {
		if err := os.WriteFile(filepath.Join(dir, m.name), []byte(m.sql), 0o600); err != nil {
			t.Fatalf("write probe migration %s: %v", m.name, err)
		}
	}
	return dir
}

// dropProbeArtefacts removes everything the probe migrations created, including
// their schema_migrations rows, so repeat runs start from the same state and
// the shared test database is left as it was found.
func dropProbeArtefacts(ctx context.Context, t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	// DROP TABLE first: the column added by 003 depends on the enum type.
	stmts := []string{
		`DROP TABLE IF EXISTS ` + probeVersionPrefix + `table`,
		`DROP TYPE IF EXISTS ` + probeVersionPrefix + `mood`,
		`DELETE FROM schema_migrations WHERE version LIKE '` + probeVersionPrefix + `%'`,
	}
	for _, stmt := range stmts {
		if _, err := pool.Exec(ctx, stmt); err != nil {
			t.Errorf("clean up probe artefacts (%s): %v", stmt, err)
		}
	}
}
