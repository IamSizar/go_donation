// retire_one.go: RetireDirectThreadInTx, the retire run of
// RetireAllDirectThreads applied to ONE chat_threads row inside the caller's
// transaction (OPOS #26466).
//
// Its caller is the Trash restore (handlers.AdminTrashHandler.Restore). The
// Trash sat outside the retirement of direct chats: a direct chat deleted while
// open, or deleted before the production run, came back open, and its two
// participants could carry on in a conversation the product had closed. The
// owner's decision (2026-09-15) is that a restored direct chat comes back
// exactly as the run leaves every direct chat: ended and archived.
//
// The statements are the run's own two, each with an id condition appended, so
// the rules, the reason text and the stamps it keeps cannot drift from the
// run's.
package chatlifecycle

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// The id placeholders below are numbered one past the highest placeholder in
// each base statement in retire.go ($1-$2 and $1). A base statement that gains
// a parameter must renumber these too; TestRetireDirectThreadInTxRetiresOnlyThatThread
// fails if they drift.
const (
	// endAndArchiveOneSQL is endAndArchiveOpenSQL restricted to one thread,
	// whose id is $3.
	endAndArchiveOneSQL = endAndArchiveOpenSQL + ` AND id = $3`

	// archiveEndedOneSQL is archiveEndedSQL restricted to one thread, whose id
	// is $2.
	archiveEndedOneSQL = archiveEndedSQL + ` AND id = $2`
)

// RetireDirectThreadInTx retires chat_threads row threadID inside tx, by the
// rules RetireAllDirectThreads applies to every direct thread:
//   - open or paused: ended and archived, with the run's reason and actorID as
//     the one who ended it (RetireResult.Ended is 1). An archive stamp the
//     thread already carries is kept whole;
//   - ended but still visible to its participants: archived by actorID, and its
//     end stamp is kept (RetireResult.Archived is 1);
//   - ended and archived, a kind='support' thread, or no such thread: nothing
//     changes, and the zero RetireResult is returned.
//
// The caller owns the transaction and has already authorised actorID, so this
// neither checks that actorID is dashboard staff nor commits. The two
// statements run in the bulk run's order (see retireInTx). A database error is
// returned wrapped, and the caller's rollback then discards the whole
// transaction.
func RetireDirectThreadInTx(ctx context.Context, tx pgx.Tx, threadID, actorID int64) (RetireResult, error) {
	ended, err := tx.Exec(ctx, endAndArchiveOneSQL, directRetireReason, actorID, threadID)
	if err != nil {
		return RetireResult{}, fmt.Errorf("retire direct thread %d: end open/paused: %w", threadID, err)
	}
	archived, err := tx.Exec(ctx, archiveEndedOneSQL, actorID, threadID)
	if err != nil {
		return RetireResult{}, fmt.Errorf("retire direct thread %d: archive ended: %w", threadID, err)
	}
	return RetireResult{Ended: int(ended.RowsAffected()), Archived: int(archived.RowsAffected())}, nil
}
