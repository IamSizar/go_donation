// Command retire-direct-chats is a one-off ops script for OPOS #25284 Phase 4:
// ends and archives every existing open kind='direct' chat_threads row, now
// that new direct-chat creation is refused server-side (see
// internal/chat.Store.RequestThread). Safe to re-run — already-ended threads
// are skipped. Usage:
//
//	go run ./cmd/retire-direct-chats -actor=<staff_user_id>
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
)

func main() {
	actor := flag.Int64("actor", 0, "staff/admin user id to attribute this bulk action to (required)")
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

	count, err := chatlifecycle.RetireAllDirectThreads(context.Background(), pool, *actor)
	if err != nil {
		log.Fatalf("retire-direct-chats: %v", err)
	}
	fmt.Printf("retire-direct-chats: ended+archived %d thread(s)\n", count)
}
