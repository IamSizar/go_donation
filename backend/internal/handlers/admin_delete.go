package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// AdminDeleteHandler exposes hard-delete endpoints for Phase 13.
//
// Pattern: every handler runs `DELETE FROM <table> WHERE id = $1` and returns:
//   - 200 {success, id}                     — row deleted
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

// deleteRow moves a row to the Trash instead of hard-deleting it (Phase 7 ·
// G-06 / A-16): it snapshots the whole row as a JSON document into trash_items,
// then removes it from the source table — both in one transaction, so a row is
// never lost nor left half-deleted. A Super-Admin can later restore or purge it.
// Returns nothing — the caller's handler ends after calling this.
func (h *AdminDeleteHandler) deleteRow(c *gin.Context, table string) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()

	// Who performed the delete (for the trash audit trail).
	var actor *int64
	if u, ok := auth.UserFromGin(c); ok && u != nil {
		actor = &u.UserID
	}

	tx, err := h.Pool.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
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
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}

	// 2) Archive it into the central trash container.
	if _, err = tx.Exec(ctx,
		`INSERT INTO trash_items (source_table, row_id, payload, deleted_by)
		 VALUES ($1, $2, $3, $4)`, table, id, payload, actor,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
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
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}

	if err = tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "trashed": true})
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
