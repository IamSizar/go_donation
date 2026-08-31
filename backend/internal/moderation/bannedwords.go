// Package moderation backs the admin-managed banned-words blocklist (#25) and
// the comment-content check that uses it. A comment whose body contains a
// banned word is held for review (status 'pending', flagged) instead of going
// live.
package moderation

import (
	"context"
	"errors"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Word is one blocklist entry.
type Word struct {
	ID        int64     `json:"id"`
	Word      string    `json:"word"`
	CreatedAt time.Time `json:"created_at"`
}

type Store struct {
	Pool *pgxpool.Pool

	// cache holds the lowercased word list so the hot path (every comment
	// submit) doesn't hit the DB. Refreshed on any admin mutation.
	mu     sync.RWMutex
	cache  []string
	loaded bool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// List returns all banned words, newest first.
func (s *Store) List(ctx context.Context) ([]Word, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT id, word, created_at FROM banned_words ORDER BY word ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Word{}
	for rows.Next() {
		var w Word
		if err := rows.Scan(&w.ID, &w.Word, &w.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

// Add inserts a new banned word (stored lowercased, trimmed). Duplicate → error.
func (s *Store) Add(ctx context.Context, word string, actorID *int64) (*Word, error) {
	word = strings.ToLower(strings.TrimSpace(word))
	if word == "" {
		return nil, errors.New("word is required")
	}
	var w Word
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO banned_words (word, created_by) VALUES ($1, $2)
		 RETURNING id, word, created_at`,
		word, actorID,
	).Scan(&w.ID, &w.Word, &w.CreatedAt)
	if err != nil {
		if strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return nil, errors.New("that word is already blocked")
		}
		return nil, err
	}
	s.invalidate()
	return &w, nil
}

// NOTE — there is deliberately no Delete method here.
//
// N3 routed the admin delete through handlers.trashRow so a removed word lands
// in المهملات and can be brought back. A Store.Delete sitting beside it would be
// a hard delete that bypasses the Trash entirely, one call away from any future
// caller, so it was removed rather than left as a trap. Anything that removes a
// word must go through the trashing path and then call Invalidate.

// Contains reports whether text contains any banned word (case-insensitive
// substring match on word boundaries-agnostic — a blocked word matches even
// inside longer text, which is the safer default for a blocklist).
func (s *Store) Contains(ctx context.Context, text string) (bool, error) {
	words, err := s.words(ctx)
	if err != nil {
		return false, err
	}
	if len(words) == 0 {
		return false, nil
	}
	lower := strings.ToLower(text)
	for _, w := range words {
		if w != "" && strings.Contains(lower, w) {
			return true, nil
		}
	}
	return false, nil
}

// words returns the cached lowercased list, loading it on first use.
func (s *Store) words(ctx context.Context) ([]string, error) {
	s.mu.RLock()
	if s.loaded {
		defer s.mu.RUnlock()
		return s.cache, nil
	}
	s.mu.RUnlock()

	rows, err := s.Pool.Query(ctx, `SELECT word FROM banned_words`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	list := []string{}
	for rows.Next() {
		var w string
		if err := rows.Scan(&w); err != nil {
			return nil, err
		}
		list = append(list, strings.ToLower(strings.TrimSpace(w)))
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	s.mu.Lock()
	s.cache = list
	s.loaded = true
	s.mu.Unlock()
	return list, nil
}

// Invalidate drops the cached word list so the next check re-reads the table.
//
// WHY IT IS EXPORTED. The blocklist is cached in-process with NO TTL, so the
// cache is only ever correct because every mutation path calls this. Two of
// those paths now live OUTSIDE this package: the admin delete routes the word
// through handlers.trashRow (so the row lands in المهملات), and a Super-Admin
// restore re-inserts it with a raw INSERT from the trash snapshot. Neither
// touches this Store, and a restored word that is missing from the cache
// silently stops being banned — the failure this export exists to prevent.
func (s *Store) Invalidate() { s.invalidate() }

func (s *Store) invalidate() {
	s.mu.Lock()
	s.loaded = false
	s.cache = nil
	s.mu.Unlock()
}
