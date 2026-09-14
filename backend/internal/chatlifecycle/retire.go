package chatlifecycle

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// RetireAllDirectThreads transitions every currently-open kind='direct'
// chat_threads row through end then archive, in one pass. Idempotent: a
// thread already ended (lifecycle != 'open') is skipped on a re-run, so this
// is safe to run more than once. Part of OPOS #25284 Phase 4's retirement of
// the old donor<->owner direct chat — kind='support' rows are never selected
// here and are left untouched.
func RetireAllDirectThreads(ctx context.Context, pool *pgxpool.Pool, actorID int64) (int, error) {
	rows, err := pool.Query(ctx, `SELECT id FROM chat_threads WHERE kind = 'direct' AND lifecycle = 'open'`)
	if err != nil {
		return 0, err
	}
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	const reason = "OPOS #25284 Phase 4 — direct donor-owner chat retired"
	for _, id := range ids {
		if _, err := Apply(ctx, pool, KindDonor, id, ActionEnd, reason, actorID); err != nil {
			return 0, err
		}
		if _, err := Apply(ctx, pool, KindDonor, id, ActionArchive, reason, actorID); err != nil {
			return 0, err
		}
	}
	return len(ids), nil
}
