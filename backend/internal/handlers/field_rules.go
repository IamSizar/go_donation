package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// FieldRulesHandler powers the admin-configurable registration field rules
// (#43). A public GET feeds the app's form validation; admin routes toggle
// whether each optional field is required.
type FieldRulesHandler struct {
	Pool *pgxpool.Pool
}

func NewFieldRulesHandler(pool *pgxpool.Pool) *FieldRulesHandler {
	return &FieldRulesHandler{Pool: pool}
}

type fieldRule struct {
	FieldKey     string `json:"field_key"`
	Required     bool   `json:"required"`
	DisplayOrder int    `json:"display_order"`
}

func (h *FieldRulesHandler) list(c *gin.Context) ([]fieldRule, bool) {
	rows, err := h.Pool.Query(c.Request.Context(),
		`SELECT field_key, (required = 1), display_order
		   FROM registration_field_rules ORDER BY display_order, field_key`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return nil, false
	}
	defer rows.Close()
	out := []fieldRule{}
	for rows.Next() {
		var r fieldRule
		if err := rows.Scan(&r.FieldKey, &r.Required, &r.DisplayOrder); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return nil, false
		}
		out = append(out, r)
	}
	return out, true
}

// PublicList — GET /api/registration/field-rules. Returns {required: [keys]} so
// the app knows which optional fields to enforce.
func (h *FieldRulesHandler) PublicList(c *gin.Context) {
	rules, ok := h.list(c)
	if !ok {
		return
	}
	required := []string{}
	for _, r := range rules {
		if r.Required {
			required = append(required, r.FieldKey)
		}
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "required": required})
}

// AdminList — GET /api/admin/registration/field-rules (full rows).
func (h *FieldRulesHandler) AdminList(c *gin.Context) {
	rules, ok := h.list(c)
	if !ok {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": rules})
}

// SetRequired — POST /api/admin/registration/field-rules/:key — body {required: bool}.
func (h *FieldRulesHandler) SetRequired(c *gin.Context) {
	key := strings.TrimSpace(c.Param("key"))
	var req struct {
		Required bool `json:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	v := 0
	if req.Required {
		v = 1
	}
	ct, err := h.Pool.Exec(c.Request.Context(),
		`UPDATE registration_field_rules SET required = $2 WHERE field_key = $1`, key, v)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Unknown field."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "field_key": key, "required": req.Required})
}
