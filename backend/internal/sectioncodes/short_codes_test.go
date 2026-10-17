package sectioncodes_test

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/sectioncodes"
)

// Client note: codes are one letter plus a running number (Z1, Z2, Z3 …), and
// every section that uses the same letter draws from the same counter.
func TestShortCodesShareOneCounterPerLetter(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	const letter = "TESTQ"
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM code_sequences WHERE prefix = $1`, letter) })
	_, _ = pool.Exec(ctx, `DELETE FROM code_sequences WHERE prefix = $1`, letter)

	for i, want := range []string{"TESTQ1", "TESTQ2", "TESTQ3"} {
		got, err := sectioncodes.NextForPrefix(ctx, pool, letter)
		if err != nil {
			t.Fatalf("call %d: %v", i, err)
		}
		if got != want {
			t.Fatalf("call %d: got %q, want %q", i, got, want)
		}
	}
}
