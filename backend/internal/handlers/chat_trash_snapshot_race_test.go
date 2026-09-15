// chat_trash_snapshot_race_test.go — the Trash must hold the chat that was
// actually deleted (OPOS #26466).
//
// trashChatThread copies a thread and its children into trash_items and deletes
// them, in one transaction. Before this fix the copy was a plain SELECT, which
// takes no lock under READ COMMITTED. A write another transaction had made but
// not yet committed was invisible to the copy. The DELETE that followed then
// waited for that write, and removed the row it produced. So the Trash held an
// earlier version than the one deleted:
//   - a thread staff ended, or cmd/retire-direct-chats ended and archived, went
//     into the Trash still open, and a restore reopened it;
//   - a message sent at that moment was missing from the copy, and the delete's
//     cascade removed it: lost for good.
//
// Each test holds the concurrent write open in a transaction of its own and
// sends the delete through the real DELETE route. It commits the write only
// once Postgres reports the delete's connection waiting on it. There are no
// sleeps: each check is a round trip. Whichever of the delete's statements
// waits, the snapshot must equal the row as the write committed it.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_trash_race
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_trash_race?sslmode=disable' \
//	  go test ./internal/handlers/ -run 'TestTrashChatThread_Snapshot' -v
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// trashRaceTimeout is a failsafe against a hung test, not a timing assumption:
// the write commits when the delete is observed waiting, never on a clock.
const trashRaceTimeout = 2 * time.Minute

// trashRaceDeleteApp is the application_name of every connection the delete
// runs on. It lets a test pick out the delete's own backend in
// pg_stat_activity, and not another test run's backend waiting on something
// else.
var trashRaceDeleteApp = "handlers-trash-race-delete-" + strconv.Itoa(os.Getpid())

// ─── Harness ────────────────────────────────────────────────────────────

// trashRace is one direct thread, the staff member who deletes it, and the two
// pools a race needs.
type trashRace struct {
	// pool seeds the thread, holds the concurrent write and watches
	// pg_stat_activity.
	pool *pgxpool.Pool
	// router serves the delete from a pool whose connections are all named
	// trashRaceDeleteApp.
	router *gin.Engine
	staff  trashRestoreStaff
	thread chatFixture
}

// newTrashRace seeds an open direct thread and wires the delete route.
func newTrashRace(t *testing.T) *trashRace {
	t.Helper()
	pool := newLifecyclePool(t)
	return &trashRace{
		pool:   pool,
		router: newLifecycleRouter(appNamedPool(t, trashRaceDeleteApp)),
		staff:  newTrashRestoreStaff(t, pool),
		thread: seedDonorChat(t, pool),
	}
}

// appNamedPool opens a second pool on the test database whose connections all
// carry app as their application_name.
func appNamedPool(t *testing.T, app string) *pgxpool.Pool {
	t.Helper()
	cfg, err := pgxpool.ParseConfig(os.Getenv("TEST_DATABASE_URL"))
	if err != nil {
		t.Fatalf("parse TEST_DATABASE_URL: %v", err)
	}
	cfg.ConnConfig.RuntimeParams["application_name"] = app
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatalf("connect the %s pool: %v", app, err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// deleteOutcome is the delete route's answer, handed back from the goroutine
// that sent it.
type deleteOutcome struct {
	code int
	body string
}

// heldWrite makes the concurrent change inside holder, which stays open, and
// returns the thread row as that change leaves it, as to_jsonb.
type heldWrite func(ctx context.Context, holder pgx.Tx) (threadRow []byte, err error)

// deleteWhileHeld runs write in a transaction it keeps open, sends the delete,
// commits the write once the delete is waiting on it, and waits for the delete
// to succeed. It returns the thread row as the write committed it.
func (rc *trashRace) deleteWhileHeld(t *testing.T, write heldWrite) []byte {
	t.Helper()
	ctx := context.Background()
	holder, err := rc.pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin the concurrent write: %v", err)
	}
	// A no-op once Commit has succeeded.
	defer func() { _ = holder.Rollback(ctx) }()

	var holderPID int32
	if err := holder.QueryRow(ctx, `SELECT pg_backend_pid()`).Scan(&holderPID); err != nil {
		t.Fatalf("read the concurrent write's backend pid: %v", err)
	}
	committedRow, err := write(ctx, holder)
	if err != nil {
		t.Fatalf("make the concurrent write: %v", err)
	}

	done := rc.startDelete(t)
	rc.commitOnceDeleteWaits(t, holder, holderPID, done)
	return committedRow
}

// startDelete sends the DELETE on a goroutine, because it is expected to wait
// on the held write.
func (rc *trashRace) startDelete(t *testing.T) <-chan deleteOutcome {
	t.Helper()
	body, err := json.Marshal(map[string]string{"password": trashRestoreDeletePassword})
	if err != nil {
		t.Fatalf("encode the delete body: %v", err)
	}
	path := adminThreadPath(rc.thread.Kind, rc.thread.ThreadID)
	done := make(chan deleteOutcome, 1)
	go func() {
		req := httptest.NewRequest(http.MethodDelete, path, bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+rc.staff.deleterToken)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		rc.router.ServeHTTP(rec, req)
		done <- deleteOutcome{code: rec.Code, body: rec.Body.String()}
	}()
	return done
}

// commitOnceDeleteWaits commits holder as soon as the delete is waiting on it,
// then waits for the delete to answer 200.
func (rc *trashRace) commitOnceDeleteWaits(t *testing.T, holder pgx.Tx, holderPID int32, done <-chan deleteOutcome) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), trashRaceTimeout)
	defer cancel()
	if err := rc.waitForDeleteToWait(ctx, holderPID, done); err != nil {
		t.Fatalf("%v (rolling back the concurrent write: %v)", err, holder.Rollback(context.Background()))
	}
	if err := holder.Commit(ctx); err != nil {
		t.Fatalf("commit the concurrent write: %v", err)
	}
	select {
	case out := <-done:
		if out.code != http.StatusOK {
			t.Fatalf("delete: status %d body %s", out.code, out.body)
		}
	case <-ctx.Done():
		t.Fatalf("the delete did not finish after the concurrent write committed: %v", ctx.Err())
	}
}

// waitForDeleteToWait returns once a backend of the delete's pool is waiting
// on a lock the holder's backend holds. If the delete answers first, it never
// waited, so the race was not reproduced and the test cannot judge the fix.
func (rc *trashRace) waitForDeleteToWait(ctx context.Context, holderPID int32, done <-chan deleteOutcome) error {
	for {
		select {
		case out := <-done:
			return fmt.Errorf("the delete answered (status %d, body %s) without waiting on the concurrent write, "+
				"so the race was not reproduced", out.code, out.body)
		default:
		}
		var waiting bool
		if err := rc.pool.QueryRow(ctx, `
			SELECT EXISTS (SELECT 1 FROM pg_stat_activity
			                WHERE application_name = $2 AND $1::int = ANY (pg_blocking_pids(pid)))`,
			holderPID, trashRaceDeleteApp).Scan(&waiting); err != nil {
			return fmt.Errorf("watch for the delete to wait on the concurrent write: %w", err)
		}
		if waiting {
			return nil
		}
	}
}

// trashSnapshot reads the thread's trash entry and returns the thread row it
// holds, without the children, alongside the children keyed by table.
func (rc *trashRace) trashSnapshot(t *testing.T) (threadRow map[string]any, children map[string]any) {
	t.Helper()
	var raw []byte
	if err := rc.pool.QueryRow(context.Background(),
		`SELECT payload FROM trash_items WHERE source_table = $1 AND row_id = $2 AND restored_at IS NULL`,
		rc.thread.ThreadTable, rc.thread.ThreadID).Scan(&raw); err != nil {
		t.Fatalf("no trash entry for %s/%d: %v", rc.thread.ThreadTable, rc.thread.ThreadID, err)
	}
	threadRow = decodeJSONObject(t, raw)
	children, ok := threadRow[chatChildrenKey].(map[string]any)
	if !ok {
		t.Fatalf("trash entry for %s/%d has no %s object: %v", rc.thread.ThreadTable, rc.thread.ThreadID, chatChildrenKey, threadRow)
	}
	delete(threadRow, chatChildrenKey)
	return threadRow, children
}

// decodeJSONObject decodes one JSON object, as to_jsonb returns it.
func decodeJSONObject(t *testing.T, raw []byte) map[string]any {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatalf("decode %s: %v", raw, err)
	}
	return out
}

// childRowIDs lists the ids of one child table's rows in a snapshot.
func childRowIDs(children map[string]any, table string) []int64 {
	rows, _ := children[table].([]any)
	ids := make([]int64, 0, len(rows))
	for _, r := range rows {
		row, _ := r.(map[string]any)
		if id, ok := row["id"].(float64); ok {
			ids = append(ids, int64(id))
		}
	}
	return ids
}

// ─── The races ──────────────────────────────────────────────────────────

// TestTrashChatThread_SnapshotKeepsAnEndThatLandsDuringTheDelete races the
// delete against the retire run's END and ARCHIVE of the same direct thread.
// The Trash must hold the thread ended and archived: holding it open is what
// let a restore reopen a retired conversation.
func TestTrashChatThread_SnapshotKeepsAnEndThatLandsDuringTheDelete(t *testing.T) {
	rc := newTrashRace(t)
	retirer := makeLifecycleUser(t, rc.pool, "admin")

	committed := rc.deleteWhileHeld(t, func(ctx context.Context, holder pgx.Tx) ([]byte, error) {
		var row []byte
		err := holder.QueryRow(ctx, `
			UPDATE chat_threads AS t
			   SET lifecycle            = 'ended',
			       lifecycle_reason     = $2,
			       lifecycle_changed_at = CURRENT_TIMESTAMP,
			       lifecycle_changed_by = $3,
			       archived_at          = CURRENT_TIMESTAMP,
			       archived_by          = $3,
			       updated_at           = CURRENT_TIMESTAMP
			 WHERE t.id = $1
			RETURNING to_jsonb(t.*)`, rc.thread.ThreadID, retiredDirectChatReason, retirer).Scan(&row)
		return row, err
	})

	got, _ := rc.trashSnapshot(t)
	if want := decodeJSONObject(t, committed); !reflect.DeepEqual(got, want) {
		t.Fatalf("the Trash holds thread %d with lifecycle %v, archived_at %v, but the delete removed it with "+
			"lifecycle %v, archived_at %v; a restore would bring back a state the thread no longer had.\n"+
			"  trash   %v\n  deleted %v",
			rc.thread.ThreadID, got["lifecycle"], got["archived_at"], want["lifecycle"], want["archived_at"], got, want)
	}
	if n := countRows(t, rc.pool, "chat_threads", "id", rc.thread.ThreadID); n != 0 {
		t.Errorf("chat_threads/%d is still live after the delete", rc.thread.ThreadID)
	}
}

// TestTrashChatThread_SnapshotKeepsAMessageSentDuringTheDelete races the delete
// against a participant's send into the same thread, made with
// chat.Store.PostMessage's two writes, in its order. The message must be in
// the Trash, because the delete removes it from chat_messages either way.
func TestTrashChatThread_SnapshotKeepsAMessageSentDuringTheDelete(t *testing.T) {
	rc := newTrashRace(t)
	var messageID int64

	committed := rc.deleteWhileHeld(t, func(ctx context.Context, holder pgx.Tx) ([]byte, error) {
		if err := holder.QueryRow(ctx, `
			INSERT INTO chat_messages (thread_id, sender_user_id, sender_role, body)
			VALUES ($1, $2, 1, 'sent while the chat was being deleted')
			RETURNING id`, rc.thread.ThreadID, rc.thread.SenderID).Scan(&messageID); err != nil {
			return nil, err
		}
		var row []byte
		err := holder.QueryRow(ctx, `
			UPDATE chat_threads AS t SET updated_at = CURRENT_TIMESTAMP
			 WHERE t.id = $1
			RETURNING to_jsonb(t.*)`, rc.thread.ThreadID).Scan(&row)
		return row, err
	})

	got, children := rc.trashSnapshot(t)
	saved := childRowIDs(children, "chat_messages")
	if !slices.Contains(saved, messageID) {
		t.Errorf("message %d, sent while the chat was being deleted, is not in the Trash (chat_messages there: %v); "+
			"it is lost for good", messageID, saved)
	}
	if n := countRows(t, rc.pool, "chat_messages", "id", messageID); n != 0 {
		t.Errorf("message %d is still live after its thread was deleted", messageID)
	}
	if want := decodeJSONObject(t, committed); !reflect.DeepEqual(got, want) {
		t.Errorf("the Trash holds thread %d as\n  %v\nbut the delete removed\n  %v", rc.thread.ThreadID, got, want)
	}
}
