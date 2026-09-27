package handlers

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// Client meeting — support is split into two departments. A ticket or support
// chat carries one of these (or NULL: opened before the split / by an older
// app build). Staff are assigned a subset in users.support_sections.
var supportSectionValues = []string{"events", "volunteers"}

// parseSupportSection validates an optional section coming from a request.
// Empty means "not given" (nil, true); an unknown value is rejected.
func parseSupportSection(raw *string) (*string, bool) {
	if raw == nil {
		return nil, true
	}
	v := strings.ToLower(strings.TrimSpace(*raw))
	if v == "" {
		return nil, true
	}
	if !inSet(v, supportSectionValues) {
		return nil, false
	}
	return &v, true
}

// supportScope returns the sections the calling staff member may see, or nil
// when they are unrestricted: admin-level staff, and staff nobody has narrowed
// yet (empty support_sections — the pre-split behaviour).
func supportScope(ctx context.Context, pool *pgxpool.Pool, c *gin.Context) ([]string, error) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil || auth.IsAdminLevel(user) {
		return nil, nil
	}
	var mine []string
	err := pool.QueryRow(ctx, `SELECT support_sections FROM users WHERE id = $1`, user.UserID).Scan(&mine)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}
	if len(mine) == 0 {
		return nil, nil
	}
	return mine, nil
}

// supportScopeSQL appends the visibility condition for `col` to args and
// returns the SQL fragment ("" when unrestricted). Unsectioned rows stay
// visible to everyone so the legacy queue is never orphaned.
func supportScopeSQL(col string, scope []string, args *[]any) string {
	if scope == nil {
		return ""
	}
	*args = append(*args, scope)
	return "(" + col + " IS NULL OR " + col + " = ANY($" + strconv.Itoa(len(*args)) + "))"
}

// supportSectionFilterSQL is the dashboard's explicit ?section= filter.
// "none" selects the unsectioned (legacy) rows.
func supportSectionFilterSQL(col, raw string, args *[]any) string {
	v := strings.ToLower(strings.TrimSpace(raw))
	switch {
	case v == "" || v == "all":
		return ""
	case v == "none":
		return col + " IS NULL"
	case inSet(v, supportSectionValues):
		*args = append(*args, v)
		return col + " = $" + strconv.Itoa(len(*args))
	}
	return ""
}

// RequireSupportSection guards the single-item routes (/:id) of tickets and
// support chats: a staff member limited to "events" must not open, answer,
// claim or delete a "volunteers" item by typing its id. 404 rather than 403 so
// the route does not confirm the item exists. Rows outside the table's
// support scope (non-support chat threads, legacy NULL rows) pass through.
func RequireSupportSection(pool *pgxpool.Pool, table, col string) gin.HandlerFunc {
	return func(c *gin.Context) {
		scope, err := supportScope(c.Request.Context(), pool, c)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		if scope == nil {
			c.Next()
			return
		}
		id, err := strconv.ParseInt(c.Param("id"), 10, 64)
		if err != nil {
			c.Next() // the handler reports the bad id itself
			return
		}
		var section *string
		err = pool.QueryRow(c.Request.Context(),
			`SELECT `+col+` FROM `+table+` WHERE id = $1`, id).Scan(&section)
		if errors.Is(err, pgx.ErrNoRows) {
			c.Next() // the handler owns the not-found answer
			return
		}
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		if section != nil && !inSet(*section, scope) {
			c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found.", "code": "support_section_forbidden"})
			return
		}
		c.Next()
	}
}

// supportSectionStaff returns the staff to notify about a new item in a
// section: active staff explicitly assigned to it. Unassigned staff ("see
// everything") are not pushed for every item — that was the noise the split
// exists to remove — they still see it in the dashboard list.
func supportSectionStaff(ctx context.Context, pool *pgxpool.Pool, section string) []int64 {
	rows, err := pool.Query(ctx, `
		SELECT id FROM users
		 WHERE $1 = ANY(support_sections)
		   AND staff_tier IS NOT NULL AND staff_tier <> '' AND staff_tier <> 'user'
		   AND COALESCE(account_status, 'active') = 'active'`, section)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := []int64{}
	for rows.Next() {
		var id int64
		if rows.Scan(&id) == nil {
			out = append(out, id)
		}
	}
	return out
}

// SetStaffSupportSections — POST /api/admin/users/:id/support_sections
// {"sections": ["events"]}. Admin tier only (route-gated): deciding which
// department a staff member answers for is an organisational call, not
// something a supervisor grants themselves. An empty list = all sections.
func SetStaffSupportSections(pool *pgxpool.Pool) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, ok := parseID(c)
		if !ok {
			return
		}
		var req struct {
			Sections []string `json:"sections"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
			return
		}
		clean := []string{}
		for _, raw := range req.Sections {
			v := strings.ToLower(strings.TrimSpace(raw))
			if !inSet(v, supportSectionValues) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid section. Allowed: " + strings.Join(supportSectionValues, ", ")})
				return
			}
			if !inSet(v, clean) {
				clean = append(clean, v)
			}
		}
		ct, err := pool.Exec(c.Request.Context(),
			`UPDATE users SET support_sections = $1 WHERE id = $2`, clean, id)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		if ct.RowsAffected() == 0 {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "User not found."})
			return
		}
		c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "support_sections": clean})
	}
}
