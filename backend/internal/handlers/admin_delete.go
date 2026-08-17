package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/casevolchat"
)

// AdminDeleteHandler exposes the delete endpoints for Phase 13.
//
// Pattern: every handler moves the row to the Trash via trashRow and returns:
//   - 200 {success, id, trashed}            — row moved to the Trash
//   - 404 {success:false, error}            — id not found
//   - 409 {success:false, error}            — FK violation (row is referenced
//     by another table). Includes the
//     Postgres "detail" string so the
//     admin sees which child rows are
//     blocking, e.g.
//     "violates foreign key constraint
//     ... on table sponsorships."
//   - 500 {success:false, error}            — any other DB error
//
// All routes are wired under the `admin` group; RequireAdmin authenticates
// before any of these run.
type AdminDeleteHandler struct {
	Pool *pgxpool.Pool
}

func NewAdminDeleteHandler(pool *pgxpool.Pool) *AdminDeleteHandler {
	return &AdminDeleteHandler{Pool: pool}
}

// deleteRow is the AdminDeleteHandler entry point: parse the :id and trash it.
func (h *AdminDeleteHandler) deleteRow(c *gin.Context, table string) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	trashRow(c, h.Pool, table, id)
}

// trashRow moves a row to the Trash instead of hard-deleting it (Phase 7 ·
// G-06 / A-16): it snapshots the whole row as a JSON document into trash_items,
// then removes it from the source table — both in one transaction, so a row is
// never lost nor left half-deleted. A Super-Admin can later restore or purge it.
//
// H15 — this used to be a private method on AdminDeleteHandler, which is the
// whole reason 15 of the 31 admin delete routes hard-deleted instead: the
// catalogue, task and comment handlers live in other files with their own
// stores and simply could not reach it. It is a package-level function now, so
// "delete" means the same thing wherever it is written.
//
// It writes the HTTP response itself and reports whether the row was trashed,
// so a caller with a side effect to run afterwards (a cache to invalidate, a
// notification to send) can key off the result instead of guessing.
//
// `table` MUST be a literal from this package — it is interpolated into the SQL.
// Never pass anything derived from a request.
func trashRow(c *gin.Context, pool *pgxpool.Pool, table string, id int64) bool {
	ctx := c.Request.Context()

	// Who performed the delete (for the trash audit trail).
	var actor *int64
	if u, ok := auth.UserFromGin(c); ok && u != nil {
		actor = &u.UserID
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}
	defer tx.Rollback(ctx)

	// 1) Snapshot the full row as a JSON document (for a faithful restore).
	var payload []byte
	err = tx.QueryRow(ctx,
		"SELECT to_jsonb(t.*) FROM "+table+" t WHERE t.id = $1", id,
	).Scan(&payload)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
			return false
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}

	// 2) Archive it into the central trash container.
	if _, err = tx.Exec(ctx,
		`INSERT INTO trash_items (source_table, row_id, payload, deleted_by)
		 VALUES ($1, $2, $3, $4)`, table, id, payload, actor,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}

	// 3) Remove from the source table. FK cascades still fire for child rows;
	//    those children are not individually trashed (restoring the parent
	//    brings back the parent row only).
	if _, err = tx.Exec(ctx, "DELETE FROM "+table+" WHERE id = $1", id); err != nil {
		// Translate FK violation (23503) into a friendly 409 so admins
		// understand why a row can't be deleted yet.
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23503" {
			msg := "Cannot delete: still referenced by another record."
			if pgErr.Detail != "" {
				msg = msg + " " + pgErr.Detail
			}
			c.JSON(http.StatusConflict, gin.H{"success": false, "error": msg})
			return false
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}

	if err = tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "trashed": true})
	return true
}

// ===== one handler per resource (mirrors admin_edit.go) =====

func (h *AdminDeleteHandler) Partner(c *gin.Context)   { h.deleteRow(c, "partners") }
func (h *AdminDeleteHandler) Media(c *gin.Context)     { h.deleteRow(c, "media_posts") }
func (h *AdminDeleteHandler) Community(c *gin.Context) { h.deleteRow(c, "city_directory_entries") }
func (h *AdminDeleteHandler) Marriage(c *gin.Context)  { h.deleteRow(c, "marriage_profiles") }
func (h *AdminDeleteHandler) MarketplaceProduct(c *gin.Context) {
	h.deleteRow(c, "marketplace_products")
}
func (h *AdminDeleteHandler) MarketplaceOrder(c *gin.Context) { h.deleteRow(c, "marketplace_orders") }
func (h *AdminDeleteHandler) BeneficiaryCase(c *gin.Context)  { h.deleteRow(c, "beneficiary_cases") }
func (h *AdminDeleteHandler) ProjectRequest(c *gin.Context) {
	h.deleteRow(c, "beneficiary_project_requests")
}
func (h *AdminDeleteHandler) Sponsorship(c *gin.Context)    { h.deleteRow(c, "sponsorships") }
func (h *AdminDeleteHandler) InKindDonation(c *gin.Context) { h.deleteRow(c, "in_kind_donations") }
func (h *AdminDeleteHandler) SupportTicket(c *gin.Context)  { h.deleteRow(c, "support_tickets") }
func (h *AdminDeleteHandler) Donation(c *gin.Context)       { h.deleteRow(c, "donations") }
func (h *AdminDeleteHandler) VolunteerApplication(c *gin.Context) {
	h.deleteRow(c, "volunteer_applications")
}
func (h *AdminDeleteHandler) Campaign(c *gin.Context) { h.deleteRow(c, "campaigns") }
func (h *AdminDeleteHandler) User(c *gin.Context)     { h.deleteRow(c, "users") }

// Phase 22 — mission delete CASCADEs signups via the FK (volunteer_mission_signups
// fk_volunteer_mission_signups_mission ON DELETE CASCADE). Volunteers who had
// joined won't get a notification on cascade; if you need that, use a status
// transition to 'cancelled' instead (fires notifications via the signup path).
func (h *AdminDeleteHandler) VolunteerMission(c *gin.Context) { h.deleteRow(c, "volunteer_missions") }

// VolunteerMissionSignup deletes ONE signup — a single volunteer's request to
// join one mission — as opposed to VolunteerMission above, which removes the
// mission and cascades every signup on it.
//
// E15 — the client asked تسجيلات المهام for a fixed five-action list
// (موافق/قبول/رفض/تراجع/حذف). The first four are status transitions that
// already existed on adminStatusH.MissionSignup; حذف had no route of any kind,
// so the dashboard's action menu had nothing it could call. This is that route,
// and it goes through trashRow like the other recoverable deletes rather than
// running a DELETE of its own: a signup is not a catalogue row — it carries the
// volunteer's own completion note and the hours they served — so pressing حذف on
// the wrong row has to be undoable from المهملات (H15's rule).
//
// THE CASCADE, AND WHY THIS ROUTE REFUSES INSTEAD OF DELETING.
//
// Deleting a signup cascades its conversation (migration 061):
//
//	volunteer_mission_signups
//	  └─ case_volunteer_chat_threads   (signup_id ... ON DELETE CASCADE)
//	       ├─ case_volunteer_chat_messages
//	       └─ case_volunteer_chat_reads
//
// trashRow snapshots only the row it deletes, so those children were destroyed
// outright and المهملات handed back the signup alone. That is worse than an
// unrecoverable delete with no Trash entry, because the operator has been told
// the action is undoable — they press حذف believing the conversation is safe.
//
// TWO WAYS TO FIX IT, AND WHY THIS ONE.
//
// (a) Archive the cascaded children into the trash payload so restore is
// faithful. Rejected. It turns trash_items from a flat row snapshot into a
// nested tree, and Restore — which admin_trash.go already flags as the place a
// mistake becomes "a worse bug than the one being fixed" — would have to
// re-insert three tables in FK order, remap identity keys, and cope with
// senders who were themselves deleted in the meantime. That is a new mechanism
// carrying the repo's most dangerous operation, built to make a rare admin
// action tidier.
//
// (b) Refuse the delete while there is a conversation to lose. Taken. It is
// the repo's existing vocabulary — trashRow already answers 409 when a row is
// still referenced — and it satisfies the actual requirement outright: a
// delete never silently destroys messages, because it never destroys them at
// all.
//
// THE TRADE-OFF. (b) buys safety with capability: a signup that has been
// talked about cannot be removed from تسجيلات المهام at all. That is a real
// cost and it is accepted deliberately, because the operator is not left
// stuck — رفض and تراجع are status transitions that already exist on this row
// and take it out of the working list without touching a message. What is
// lost is tidying; what is kept is the conversation. (a) remains open if the
// Trash ever grows a general tree-restore, and this refusal is forward
// compatible with it.
//
// This follows K14 (marriage/owner.go), which refused to route
// marriage_profiles through trashRow for the same reason — its cascade reaches
// chat threads and the record that the user PAID. The difference is the remedy:
// K14 needed the profile to disappear from a public browse feed, so it stamped
// a soft-delete. Nothing here needs to disappear, so no new column is needed.
//
// The guard counts MESSAGES, not threads, and that distinction is the whole
// design: casevolchat.EnsureThreadForSignup opens a thread the moment a signup
// with a linked case is approved, so refusing on thread existence would have
// made nearly every approved signup undeletable — a far bigger regression than
// the bug. An empty thread has no conversation to protect and re-opens by
// itself; see MessageCountForSignup.
func (h *AdminDeleteHandler) VolunteerMissionSignup(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}

	// casevolchat.Store is a stateless wrapper over the pool, so it is built
	// here rather than injected: there is no lifecycle to share, and a nil
	// field on this handler would be a silent way to lose the guard.
	messages, err := casevolchat.New(h.Pool).MessageCountForSignup(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Database error: " + err.Error(),
		})
		return
	}
	if messages > 0 {
		// `code` is the stable key the dashboard translates through its
		// `error.*` namespace, so an Arabic operator reads Arabic; `error` is
		// the fallback for a client without that mapping. `messages` says how
		// much is at stake, which is what makes the refusal actionable.
		c.JSON(http.StatusConflict, gin.H{
			"success":  false,
			"code":     "signup_has_chat_history",
			"messages": messages,
			"error": "Cannot delete: this signup has a chat conversation, and deleting it " +
				"would permanently destroy those messages. Use reject or withdraw instead.",
		})
		return
	}

	trashRow(c, h.Pool, "volunteer_mission_signups", id)
}
