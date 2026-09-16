// Command retire-direct-chats is a one-off ops script for OPOS #25284 Phase 4.
// It retires every existing kind='direct' chat_threads row, now that new
// direct-chat creation is refused server-side (see
// internal/chat.Store.RequestThread):
//
//   - open and paused direct threads are ended and archived, keeping any
//     archive stamp staff had already set;
//   - ended direct threads that participants can still see are archived.
//
// The whole run is one transaction (a failure changes nothing), the actor
// must be dashboard staff, and a re-run changes nothing. Hardened by OPOS
// #26412; the operator's runbook is docs/runbooks/retire-direct-chats.md.
// Usage:
//
//	go run ./cmd/retire-direct-chats -actor=<staff_user_id>
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
)

func main() {
	actor := flag.Int64("actor", 0, "dashboard staff user id to attribute this bulk action to (required)")
	flag.Parse()
	if *actor <= 0 {
		log.Fatal("retire-direct-chats: -actor=<staff_user_id> is required")
	}

	// DATABASE_URL is the same env var cmd/server/main.go reads for its
	// Postgres DSN (via internal/config.Load), so this script connects to the
	// same database with the same configuration convention.
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("retire-direct-chats: DATABASE_URL is required")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		log.Fatalf("retire-direct-chats: connect: %v", err)
	}
	defer pool.Close()

	res, err := chatlifecycle.RetireAllDirectThreads(context.Background(), pool, *actor)
	// A refusal gets its own wording: it is an operator mistake with an
	// obvious fix, not a failure to investigate. log.Fatal exits with 1.
	var refused *chatlifecycle.ActorNotStaffError
	if errors.As(err, &refused) {
		log.Fatalf("retire-direct-chats: refused, nothing was changed: %v", refused)
	}
	if err != nil {
		log.Fatalf("retire-direct-chats: %v", err)
	}
	// The first line keeps the original format; the second breaks the total
	// down so it can be checked against the runbook's pre-flight counts.
	fmt.Printf("retire-direct-chats: ended+archived %d thread(s)\n", res.Total())
	fmt.Printf("retire-direct-chats: ended %d open/paused thread(s), archived %d already-ended thread(s)\n", res.Ended, res.Archived)
}
