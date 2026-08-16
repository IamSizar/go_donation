// migrate.go — the forward-only SQL migration runner.
//
// One entry point, RunMigrations, applies the *.sql files in a directory in
// filename order and records each in schema_migrations so it runs at most once.
// Callers that share a database are serialised by a Postgres advisory lock (see
// migrationsLockKey), because "at most once" has to hold across processes:
// `go test ./...` runs each package in its own process, and a rolling deploy
// can boot two server replicas with RUN_MIGRATIONS=1 at the same moment.
package db

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// migrationsLockKey is the key of the advisory lock that serialises
// RunMigrations. The value is arbitrary ("GODONATION" on a phone keypad, so
// it is recognisable in pg_locks) but must never change: two binaries holding
// different keys are not serialised against each other at all.
const migrationsLockKey int64 = 4636628466

// unlockTimeout bounds the best-effort unlock at the end of a run, so a
// database that has stopped answering cannot wedge a shutting-down caller.
const unlockTimeout = 5 * time.Second

// ─── Entry point ────────────────────────────────────────────────────────

// RunMigrations applies any *.sql files in dir that haven't been applied yet,
// in filename order, recording each in a schema_migrations table so it runs at
// most once. Files are executed with the simple query protocol so multi-
// statement migration files work. Intended for fresh databases (e.g. a new
// Railway Postgres); gated behind RUN_MIGRATIONS=1 by the caller.
//
// Concurrent callers on the same database block on an advisory lock and, once
// they get it, find the work already done and return without applying anything.
// It returns the first error encountered, leaving already-applied files
// recorded — migrations are forward-only and never rolled back here.
func RunMigrations(ctx context.Context, pool *pgxpool.Pool, dir string) error {
	// One connection for the whole run: the advisory lock is SESSION-scoped, so
	// every statement it guards — and the unlock itself — has to travel down the
	// same connection that took it.
	conn, err := pool.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("acquire conn: %w", err)
	}
	defer conn.Release()

	if err := lockMigrations(ctx, conn); err != nil {
		return err
	}
	defer unlockMigrations(conn)

	// Everything below runs under the lock, the bootstrap included: CREATE TABLE
	// IF NOT EXISTS is not atomic against a concurrent CREATE of the same table.
	if err := ensureMigrationsTable(ctx, conn); err != nil {
		return err
	}
	files, err := migrationFiles(dir)
	if err != nil {
		return err
	}
	applied, err := appliedVersions(ctx, conn)
	if err != nil {
		return err
	}

	count := 0
	for _, name := range files {
		if applied[name] {
			continue
		}
		if err := applyMigration(ctx, conn, dir, name); err != nil {
			return err
		}
		count++
		log.Printf("[migrate] applied %s", name)
	}
	log.Printf("[migrate] done: %d newly applied, %d total migration files", count, len(files))
	return nil
}

// ─── Locking ────────────────────────────────────────────────────────────

// lockMigrations blocks until this session owns the migration lock. Waiting is
// the point: the loser wakes up after the winner has recorded its work and so
// sees an up-to-date schema_migrations instead of racing it. The wait ends
// early if ctx is cancelled.
func lockMigrations(ctx context.Context, conn *pgxpool.Conn) error {
	if _, err := conn.Exec(ctx, `SELECT pg_advisory_lock($1)`, migrationsLockKey); err != nil {
		return fmt.Errorf("take migration lock: %w", err)
	}
	return nil
}

// unlockMigrations releases the lock on the session that took it. It uses its
// own short-lived context so a caller whose ctx was already cancelled still
// unlocks, and only warns on failure: the lock is session-scoped, so it is also
// dropped the moment this connection closes.
func unlockMigrations(conn *pgxpool.Conn) {
	ctx, cancel := context.WithTimeout(context.Background(), unlockTimeout)
	defer cancel()
	if _, err := conn.Exec(ctx, `SELECT pg_advisory_unlock($1)`, migrationsLockKey); err != nil {
		log.Printf("[migrate] warning: releasing migration lock: %v", err)
	}
}

// ─── Steps ──────────────────────────────────────────────────────────────

// ensureMigrationsTable creates the ledger of applied migrations if this is a
// fresh database. Call it under the lock.
func ensureMigrationsTable(ctx context.Context, conn *pgxpool.Conn) error {
	if _, err := conn.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version    TEXT PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
		)`); err != nil {
		return fmt.Errorf("ensure schema_migrations: %w", err)
	}
	return nil
}

// migrationFiles returns the names of the *.sql files in dir, sorted, which is
// the order they are applied in — hence the numeric filename prefixes.
func migrationFiles(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("read migrations dir %q: %w", dir, err)
	}
	var files []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			files = append(files, e.Name())
		}
	}
	sort.Strings(files)
	return files, nil
}

// appliedVersions reads the set of migrations this database has already run.
// Call it under the lock, so no one can add to the set while it is being read.
func appliedVersions(ctx context.Context, conn *pgxpool.Conn) (map[string]bool, error) {
	rows, err := conn.Query(ctx, `SELECT version FROM schema_migrations`)
	if err != nil {
		return nil, fmt.Errorf("load applied migrations: %w", err)
	}
	defer rows.Close()

	applied := map[string]bool{}
	for rows.Next() {
		var v string
		if err := rows.Scan(&v); err != nil {
			return nil, err
		}
		applied[v] = true
	}
	// Checked explicitly: a failure part-way through the stream would otherwise
	// look like a short list, and every row missed is a migration this run would
	// then apply a second time.
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("load applied migrations: %w", err)
	}
	return applied, nil
}

// applyMigration runs one migration file and records it. Both steps go through
// the locked connection so a concurrent caller cannot interleave with them.
func applyMigration(ctx context.Context, conn *pgxpool.Conn, dir, name string) error {
	sqlBytes, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		return fmt.Errorf("read %s: %w", name, err)
	}

	// Simple protocol: allows multiple statements in one file.
	mrr := conn.Conn().PgConn().Exec(ctx, string(sqlBytes))
	if _, err := mrr.ReadAll(); err != nil {
		return fmt.Errorf("apply %s: %w", name, err)
	}

	if _, err := conn.Exec(ctx,
		`INSERT INTO schema_migrations (version) VALUES ($1)`, name); err != nil {
		return fmt.Errorf("record %s: %w", name, err)
	}
	return nil
}
