// admin_chat_lifecycle.go — the STAFF-ONLY endpoints that end, pause, resume,
// archive, un-archive and delete a chat, in all four of the product's chat
// systems (donor↔owner, marriage, staff↔staff, case-volunteer).
//
// The rules themselves live in internal/chatlifecycle so all four systems
// share one implementation; this file is the HTTP skin plus the delete path,
// which has to preserve a thread's messages through the Trash.
//
// AUTHORIZATION — staff only, in every system.
// Every route here is registered on the `admin` route group in main.go, which
// runs RequireAdmin before any handler: a participant's mobile token cannot
// reach these handlers at all, and there is deliberately no mobile-side
// lifecycle route. On top of that each route carries the module permission
// that already governs its chat (messages / marriage / volunteers). The
// participant path is pinned by TestChatLifecycle_ParticipantCannotModerate.
package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
)

// ChatLifecycleHandler serves the lifecycle + delete routes for every chat
// system. One handler rather than four, because the behaviour is identical
// and only the table differs — the differences are already expressed once, in
// chatlifecycle.Systems().
type ChatLifecycleHandler struct {
	Pool *pgxpool.Pool
}

func NewChatLifecycleHandler(pool *pgxpool.Pool) *ChatLifecycleHandler {
	return &ChatLifecycleHandler{Pool: pool}
}

// chatLifecycleReq is the body of a lifecycle POST.
//
//	action — end | pause | resume | archive | unarchive
//	reason — optional free text shown VERBATIM to both participants in place
//	         of the composer, so a paused chat always explains itself.
type chatLifecycleReq struct {
	Action string `json:"action"`
	Reason string `json:"reason"`
}

// Apply is the shared body of every lifecycle route. `kind` is supplied by
// main.go as a compile-time constant, never from the URL, so no request value
// ever selects a table.
func (h *ChatLifecycleHandler) Apply(kind chatlifecycle.Kind) gin.HandlerFunc {
	return func(c *gin.Context) {
		user, ok := auth.UserFromGin(c)
		if !ok || user == nil {
			c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
			return
		}
		id, ok := parseID(c)
		if !ok {
			return
		}
		var req chatLifecycleReq
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
			return
		}
		state, err := chatlifecycle.Apply(c.Request.Context(), h.Pool, kind, id, req.Action, req.Reason, user.UserID)
		if err != nil {
			h.lifecycleErr(c, err)
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"success":     true,
			"id":          id,
			"kind":        string(kind),
			"lifecycle":   state.Lifecycle,
			"reason":      state.Reason,
			"is_archived": state.IsArchived,
		})
	}
}

// lifecycleErr maps the package's typed errors onto HTTP. Nothing is
// swallowed: an unrecognised error is logged with its detail and answered
// with a friendly 500.
func (h *ChatLifecycleHandler) lifecycleErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, chatlifecycle.ErrNotFound):
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Chat not found."})
	case errors.Is(err, chatlifecycle.ErrEnded):
		c.JSON(http.StatusConflict, gin.H{"success": false,
			"error": "This chat has been ended. Ending is final — start a new conversation instead."})
	case errors.Is(err, chatlifecycle.ErrNotPaused):
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This chat is not paused, so it cannot be resumed."})
	case errors.Is(err, chatlifecycle.ErrUnknownAction):
		c.JSON(http.StatusBadRequest, gin.H{"success": false,
			"error": "Unknown action. Use end, pause, resume, archive or unarchive."})
	default:
		log.Printf("[chat-lifecycle] %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
	}
}

// ─── Delete → Trash ─────────────────────────────────────────────────────

// Delete moves a whole chat thread to the Trash, from where a Super-Admin can
// restore it or destroy it permanently — the same two-step the rest of the
// product already uses.
//
// It is registered as a DELETE on the `admin` group, which is where the
// dashboard-wide delete-password middleware is mounted; this handler
// deliberately contains NO password check of its own so there is exactly one.
func (h *ChatLifecycleHandler) Delete(kind chatlifecycle.Kind) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, ok := parseID(c)
		if !ok {
			return
		}
		sys, ok := chatlifecycle.Lookup(kind)
		if !ok {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Unknown chat type."})
			return
		}
		trashChatThread(c, h.Pool, sys, id)
	}
}

// chatChildrenKey is the payload key under which a trashed chat thread's
// child rows travel. The leading underscores keep it clearly distinct from a
// real column; jsonb_populate_record (used by the restore) ignores keys that
// do not match a column, so parking the children here does not disturb the
// generic restore of the thread row itself.
const chatChildrenKey = "__chat_children"

// trashChatThread is trashRow's chat-aware sibling.
//
// WHY IT EXISTS. trashRow snapshots ONE row and lets the FK cascade take the
// children — its own comment says so. For most tables that is fine. For a
// chat it is not: chat_messages, chat_reads (and, for the donor chat, the K19
// contact-block log) all belong to the thread, so a plain trashRow would put
// an EMPTY conversation in the Trash and restore an empty conversation back
// out. A thread without its messages is worse than useless — it looks
// recovered while the actual content is gone forever.
//
// So the snapshot here is the thread row PLUS every child row, all in the one
// trash_items payload, written inside the same transaction as the delete —
// and the delete removes those children EXPLICITLY rather than trusting a
// cascade to exist, because in one of the five systems it does not (see step
// 2 below).
//
// THE SNAPSHOT IS THE ROW THAT WAS DELETED (OPOS #26466). The copy used to be
// a plain SELECT, which takes no lock under READ COMMITTED. A write another
// transaction had made but not yet committed was invisible to it: a staff END,
// the retire run's END and ARCHIVE, a message send. The DELETE that followed
// waited for that write, then removed the row it produced. So the Trash held
// a thread open that had been ended, which a restore reopened, and a message
// the cascade removed was in no snapshot at all. Now:
//   - the thread row is read FOR UPDATE. That waits for such a write to
//     commit, reads the row it left, and holds the row until this transaction
//     ends. A child insert in a system with foreign keys takes a KEY SHARE
//     lock on the row, so no message can be added meanwhile either;
//   - each child table's snapshot is the RETURNING of its own DELETE, so what
//     was saved and what was removed are the same rows by construction. Chat
//     groups have no foreign keys, so nothing stops a message being committed
//     to one after that DELETE ran: it stays behind as a live row rather than
//     being lost.
//
// A second delete of the same thread now waits on the first and then answers
// 404, instead of writing a second trash entry for it.
//
// restoreChatChildren (admin_trash.go) puts the children back after the
// generic restore has re-inserted the parent, and closeRestoredDirectChat then
// closes a direct chat. Kept as one payload rather than one trash entry per
// message so the operator restores a CONVERSATION with a single click, and
// cannot half-restore one.
func trashChatThread(c *gin.Context, pool *pgxpool.Pool, sys chatlifecycle.System, id int64) {
	ctx := c.Request.Context()

	var actor *int64
	if u, ok := auth.UserFromGin(c); ok && u != nil {
		actor = &u.UserID
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// 1) The thread row, read FOR UPDATE and so held until this transaction
	//    ends (see THE SNAPSHOT IS THE ROW THAT WAS DELETED above). A thread a
	//    concurrent request deleted is gone once the lock is granted, and is
	//    reported as not found.
	var payload []byte
	// Table name is a package-level literal from chatlifecycle's whitelist.
	err = tx.QueryRow(ctx,
		"SELECT to_jsonb(t.*) FROM "+sys.ThreadTable+" t WHERE t.id = $1 FOR UPDATE", id).Scan(&payload)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Chat not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	var row map[string]json.RawMessage
	if err := json.Unmarshal(payload, &row); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Could not snapshot this chat."})
		return
	}

	// 2) Every child row: deleted EXPLICITLY, never by relying on a cascade,
	//    and snapshotted from that same DELETE's RETURNING, keyed by its table
	//    so the restore knows where each list belongs.
	//
	//    The four pre-existing systems (012, 058, 059, 061) do declare
	//    `REFERENCES <thread table>(id) ON DELETE CASCADE` on every child, so
	//    for them this loop removes rows the cascade would have removed a
	//    moment later anyway — same end state, just stated rather than
	//    implied. chat_group_* (migration 120) has NO foreign keys at all, by
	//    that package's deliberate convention (existence is validated in
	//    chatgroups.Store instead), so for a group there is no cascade to
	//    inherit: without this loop the delete left every message, read
	//    cursor, contact-block and member row live in the database forever,
	//    and a later restore then failed outright on a duplicate key while
	//    re-inserting rows that had never gone away.
	//
	//    One statement per table, doing both the delete and the snapshot, is
	//    what keeps "what was saved" and "what was removed" provably the same
	//    rows, in all five systems alike.
	children := map[string]json.RawMessage{}
	for _, child := range sys.ChildTables() {
		var rows []byte
		if err := tx.QueryRow(ctx,
			// Table and column names are package-level literals from
			// chatlifecycle's whitelist, never request values.
			"WITH removed AS (DELETE FROM "+child+" WHERE "+sys.ChildIDColumn+" = $1 RETURNING *) "+
				"SELECT COALESCE(jsonb_agg(to_jsonb(removed.*)), '[]'::jsonb) FROM removed",
			id).Scan(&rows); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false,
				"error": "Could not move this chat's messages to the Trash: " + err.Error()})
			return
		}
		children[child] = rows
	}
	encodedChildren, err := json.Marshal(children)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Could not snapshot this chat's messages."})
		return
	}
	row[chatChildrenKey] = encodedChildren
	full, err := json.Marshal(row)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Could not snapshot this chat."})
		return
	}

	// 3) Out of the live table, then (4) into the Trash — one transaction, so
	//    the conversation is never lost nor left half-deleted.
	if _, err := tx.Exec(ctx, "DELETE FROM "+sys.ThreadTable+" WHERE id = $1", id); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23503" {
			msg := "Cannot delete: this chat is still referenced by another record."
			if pgErr.Detail != "" {
				msg += " " + pgErr.Detail
			}
			c.JSON(http.StatusConflict, gin.H{"success": false, "error": msg})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO trash_items (source_table, row_id, payload, deleted_by) VALUES ($1, $2, $3, $4)`,
		sys.ThreadTable, id, full, actor); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "trashed": true, "kind": string(sys.Kind)})
}

// restoreChatChildren puts a trashed chat's messages, read cursors and
// moderation log back after admin_trash.Restore has re-inserted the thread
// row. It is a no-op for every payload that is not a chat, so the generic
// restore path is unaffected.
//
// Child rows are inserted with jsonb_populate_record exactly as the parent
// is, which preserves their original ids — the read cursors point at message
// ids, so renumbering the messages would silently corrupt every unread badge.
//
// The destination table is never taken from the payload as text: each key is
// checked against the child tables the four registered chat systems actually
// declare, and anything else is refused. A tampered trash row therefore
// cannot name a table.
func restoreChatChildren(ctx context.Context, tx pgx.Tx, sourceTable string, payload []byte) error {
	var row map[string]json.RawMessage
	if err := json.Unmarshal(payload, &row); err != nil {
		return fmt.Errorf("decode trash payload for %s: %w", sourceTable, err)
	}
	raw, ok := row[chatChildrenKey]
	if !ok {
		return nil // not a chat thread, or trashed before this feature existed
	}
	var children map[string]json.RawMessage
	if err := json.Unmarshal(raw, &children); err != nil {
		return fmt.Errorf("decode chat children for %s: %w", sourceTable, err)
	}

	allowed := allowedChatChildTables(sourceTable)
	// Insert in the declared order (messages before reads) so a read cursor
	// never lands before the message it refers to.
	for _, table := range allowed {
		rows, ok := children[table]
		if !ok {
			continue
		}
		if _, err := tx.Exec(ctx,
			"INSERT INTO "+table+" SELECT * FROM jsonb_populate_recordset(NULL::"+table+", $1::jsonb)",
			[]byte(rows)); err != nil {
			return fmt.Errorf("restore %s rows: %w", table, err)
		}
	}
	return nil
}

// restoredDirectChatTable is the one thread table whose restores are closed on
// the way back. chatlifecycle.RetireDirectThreadInTx writes only this table,
// and only its kind='direct' rows.
const restoredDirectChatTable = "chat_threads"

// closeRestoredDirectChat closes a donor↔owner DIRECT chat that
// AdminTrashHandler.Restore has just re-inserted, inside the restore's own
// transaction (OPOS #26466). It is a no-op for every other table, and for a
// kind='support' chat.
//
// WHY. Direct messaging is retired (OPOS #25284 Phase 4): a new direct chat is
// refused with 410, and cmd/retire-direct-chats ends and archives the ones that
// exist. The Trash sat outside both. A direct chat deleted while open, or
// deleted before the retire run, came back open, and its participants could
// carry on in it. The owner's decision (2026-09-15) is "restore as closed": it
// comes back ended and archived, so staff keep its history and nobody can
// message in it again.
//
// It applies the retire run's own rules and reason, through
// chatlifecycle.RetireDirectThreadInTx, with actorID, the restoring staff
// member, recorded as the one who closed it. An end or archive stamp the chat
// already carries is kept.
//
// The thread id is read from the payload, the row the restore just inserted,
// so the chat closed is always the one restored.
//
// It returns the id it acted on and what the retirement changed, so the caller
// can log it once the restore has committed. Both are zero for a table that is
// not chat_threads.
func closeRestoredDirectChat(ctx context.Context, tx pgx.Tx, sourceTable string, payload []byte, actorID int64) (int64, chatlifecycle.RetireResult, error) {
	if sourceTable != restoredDirectChatTable {
		return 0, chatlifecycle.RetireResult{}, nil
	}
	var restored struct {
		ID int64 `json:"id"`
	}
	if err := json.Unmarshal(payload, &restored); err != nil {
		return 0, chatlifecycle.RetireResult{}, fmt.Errorf("decode the id of the restored %s row: %w", sourceTable, err)
	}
	if restored.ID == 0 {
		return 0, chatlifecycle.RetireResult{}, fmt.Errorf("the restored %s payload carries no id", sourceTable)
	}
	res, err := chatlifecycle.RetireDirectThreadInTx(ctx, tx, restored.ID, actorID)
	if err != nil {
		return 0, chatlifecycle.RetireResult{}, fmt.Errorf("close restored direct chat %d: %w", restored.ID, err)
	}
	return restored.ID, res, nil
}

// allowedChatChildTables returns the child tables of the chat system whose
// thread table is `sourceTable`, or nil when the table is not a chat thread
// table. This is the whitelist that keeps a payload key from becoming SQL.
//
// This deliberately calls chatlifecycle.AllSystems(), NOT chatlifecycle.Systems():
// a thread trashed before a system was retired from active use (e.g. a
// case_volunteer_chat_threads row, retired by OPOS #25284 Phase 4) is still
// sitting in the Trash UI and still restorable per restorableTables below —
// resolving its child tables here must keep working even though the system
// is no longer iterated for creation/listing purposes. Swapping this back to
// Systems() would silently make every such restore come back as an empty
// shell (thread row present, messages gone) — see
// TestAllowedChatChildTablesCoversEveryRestorableTable.
func allowedChatChildTables(sourceTable string) []string {
	for _, sys := range chatlifecycle.AllSystems() {
		if sys.ThreadTable == sourceTable {
			return sys.ChildTables()
		}
	}
	return nil
}
