// Package casevolchat is what remains of Note #36's Staff↔Volunteer↔
// Beneficiary direct messaging feature after OPOS #25284 Phase 4 retired it
// entirely: a volunteer and the beneficiary of the case they are helping no
// longer message each other directly (staff-created chat groups, package
// chatgroups, are the replacement coordination surface).
//
// The package survives only because case_volunteer_chat_threads and
// case_volunteer_chat_messages still hold historical rows — the Global
// Constraints for this retirement forbid dropping those tables — and
// internal/handlers/admin_delete.go's VolunteerMissionSignup delete guard
// still needs to know whether a signup's old thread carries any messages
// before it may let the signup itself be deleted. See MessageCountForSignup.
package casevolchat

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is a stateless wrapper over the pool — see MessageCountForSignup.
type Store struct {
	Pool *pgxpool.Pool
}

// New constructs a Store. Cheap enough to build inline per call (see
// admin_delete.go), since it carries no state beyond the pool.
func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// MessageCountForSignup reports how many chat messages hang off a signup, via
// its (possibly historical) thread. It returns 0 when the signup has no
// thread at all, and 0 when the thread exists but nobody ever spoke in it.
//
// It exists for the admin delete guard. volunteer_mission_signups cascades to
// case_volunteer_chat_threads (migration 061), which cascades on to its
// messages and reads — and handlers.trashRow archives only the row it
// deletes, so a delete would take the conversation with it and المهملات
// would hand back the signup alone. The caller uses this to refuse rather
// than destroy.
//
// WHY MESSAGES AND NOT THE THREAD. Before OPOS #25284 Phase 4 retired direct
// messaging, a thread was opened automatically the moment a signup with a
// linked case was approved, before anyone had typed anything. Refusing on
// the mere existence of a thread would have made nearly every approved
// signup permanently undeletable. An empty thread holds no conversation, so
// it is not worth blocking an operator over; a single message — old or new —
// is real conversation history that must not be silently destroyed.
func (s *Store) MessageCountForSignup(ctx context.Context, signupID int64) (int, error) {
	if signupID <= 0 {
		return 0, errors.New("signupID is required")
	}
	var n int
	if err := s.Pool.QueryRow(ctx, `
		SELECT COUNT(m.id)
		  FROM case_volunteer_chat_threads t
		  JOIN case_volunteer_chat_messages m ON m.thread_id = t.id
		 WHERE t.signup_id = $1`, signupID,
	).Scan(&n); err != nil {
		return 0, fmt.Errorf("count chat messages for signup %d: %w", signupID, err)
	}
	return n, nil
}
