package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// AdminTrashHandler backs the Phase 7 Trash container (G-06 / A-16): listing
// what's been deleted, restoring a row from its JSON snapshot, and permanently
// purging it (PIN-gated). Deletes land here via AdminDeleteHandler.deleteRow.
type AdminTrashHandler struct {
	Pool *pgxpool.Pool
}

func NewAdminTrashHandler(pool *pgxpool.Pool) *AdminTrashHandler {
	return &AdminTrashHandler{Pool: pool}
}

// restorableTables is the allowlist of tables a trash row may be restored into.
// It mirrors the tables AdminDeleteHandler.deleteRow can trash. Because restore
// interpolates the table name into SQL, we validate against this set first so a
// tampered source_table can never inject.
var restorableTables = map[string]bool{
	"partners":                     true,
	"media_posts":                  true,
	"city_directory_entries":       true,
	"marriage_profiles":            true,
	"marketplace_products":         true,
	"marketplace_orders":           true,
	"beneficiary_cases":            true,
	"beneficiary_project_requests": true,
	"sponsorships":                 true,
	"in_kind_donations":            true,
	"support_tickets":              true,
	"donations":                    true,
	"volunteer_applications":       true,
	"campaigns":                    true,
	"users":                        true,
	"volunteer_missions":           true,
}

// List returns everything currently in the trash (not yet restored), newest
// first, with who deleted it and the full JSON payload so the UI can preview.
// GET /api/admin/trash
func (h *AdminTrashHandler) List(c *gin.Context) {
	ctx := c.Request.Context()
	rows, err := h.Pool.Query(ctx, `
		SELECT ti.id, ti.source_table, ti.row_id, ti.deleted_by, ti.deleted_at,
		       COALESCE(up.full_name, u.username, u.phone) AS deleted_by_name,
		       ti.payload
		  FROM trash_items ti
		  LEFT JOIN users u ON u.id = ti.deleted_by
		  LEFT JOIN user_profiles up ON up.user_id = ti.deleted_by
		 WHERE ti.restored_at IS NULL
		 ORDER BY ti.deleted_at DESC
		 LIMIT 500`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer rows.Close()

	items := []gin.H{}
	for rows.Next() {
		var (
			id, rowID     int64
			table         string
			deletedBy     *int64
			deletedAt     time.Time
			deletedByName *string
			payload       []byte
		)
		if err := rows.Scan(&id, &table, &rowID, &deletedBy, &deletedAt, &deletedByName, &payload); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
			return
		}
		items = append(items, gin.H{
			"id":              id,
			"source_table":    table,
			"row_id":          rowID,
			"deleted_by":      deletedBy,
			"deleted_by_name": deletedByName,
			"deleted_at":      deletedAt,
			"payload":         json.RawMessage(payload),
		})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Restore re-inserts a trashed row back into its source table from the JSON
// snapshot and marks the trash entry restored. Note #26 — this used to be a
// single click with no confirmation, so any admin tier could accidentally
// restore a deleted record. PIN-gated the same way Purge already is: the
// caller must re-supply their own password, verified server-side.
// POST /api/admin/trash/:id/restore   body {password}
func (h *AdminTrashHandler) Restore(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Not authenticated."})
		return
	}
	var req struct {
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if strings.TrimSpace(req.Password) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Password required to restore."})
		return
	}

	ctx := c.Request.Context()

	// PIN check — verify the acting admin's own password (fails closed).
	var hash *string
	if err := h.Pool.QueryRow(ctx,
		"SELECT password_hash FROM users WHERE id = $1", user.UserID).Scan(&hash); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	if hash == nil || *hash == "" {
		c.JSON(http.StatusForbidden, gin.H{"success": false,
			"error": "No password is set on your account; ask a Super-Admin to set one."})
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(*hash), []byte(strings.TrimSpace(req.Password))) != nil {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Incorrect password."})
		return
	}

	tx, err := h.Pool.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer tx.Rollback(ctx)

	var (
		table   string
		rowID   int64
		payload []byte
	)
	err = tx.QueryRow(ctx,
		`SELECT source_table, row_id, payload FROM trash_items
		  WHERE id = $1 AND restored_at IS NULL`, id,
	).Scan(&table, &rowID, &payload)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not in trash (already restored or purged)."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if !restorableTables[table] {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "This record's table can't be restored."})
		return
	}

	// Re-hydrate the row from its JSON document. jsonb_populate_record maps the
	// payload's fields onto the table's column types; SELECT * then inserts it.
	_, err = tx.Exec(ctx,
		"INSERT INTO "+table+" SELECT * FROM jsonb_populate_record(NULL::"+table+", $1::jsonb)", payload,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			c.JSON(http.StatusConflict, gin.H{"success": false,
				"error": "A record with this id already exists — can't restore."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Restore failed: " + err.Error()})
		return
	}

	if _, err = tx.Exec(ctx, `UPDATE trash_items SET restored_at = NOW() WHERE id = $1`, id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if err = tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "restored_to": table, "row_id": rowID})
}

// Purge permanently deletes a trash entry. It is PIN-gated: the caller must
// re-supply their own password in the body, verified server-side (A-16).
// POST /api/admin/trash/:id/purge   body {password}
func (h *AdminTrashHandler) Purge(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Not authenticated."})
		return
	}
	var req struct {
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if strings.TrimSpace(req.Password) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Password required to purge."})
		return
	}

	// PIN check — verify the acting admin's own password (fails closed).
	ctx := c.Request.Context()
	var hash *string
	if err := h.Pool.QueryRow(ctx,
		"SELECT password_hash FROM users WHERE id = $1", user.UserID).Scan(&hash); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	if hash == nil || *hash == "" {
		c.JSON(http.StatusForbidden, gin.H{"success": false,
			"error": "No password is set on your account; ask a Super-Admin to set one."})
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(*hash), []byte(strings.TrimSpace(req.Password))) != nil {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Incorrect password."})
		return
	}

	ct, err := h.Pool.Exec(ctx, `DELETE FROM trash_items WHERE id = $1`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "purged": true})
}
