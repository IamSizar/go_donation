package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// FieldRulesHandler powers the admin-configurable data-collection field
// rules (#43, extended by Note 33). A public GET feeds the app's forms
// (which fields to validate as required, which to hide entirely); admin
// routes let the Main Admin set each field's state.
type FieldRulesHandler struct {
	Pool *pgxpool.Pool
}

func NewFieldRulesHandler(pool *pgxpool.Pool) *FieldRulesHandler {
	return &FieldRulesHandler{Pool: pool}
}

// fieldRuleStates is the fixed set Note 33 asks for: a field is Required,
// Optional, or completely hidden from the form.
var fieldRuleStates = []string{"required", "optional", "hidden"}

type fieldRule struct {
	FieldKey     string `json:"field_key"`
	State        string `json:"state"`
	DisplayOrder int    `json:"display_order"`
}

func (h *FieldRulesHandler) list(c *gin.Context) ([]fieldRule, bool) {
	rows, err := h.Pool.Query(c.Request.Context(),
		`SELECT field_key, state, display_order
		   FROM registration_field_rules ORDER BY display_order, field_key`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return nil, false
	}
	defer rows.Close()
	out := []fieldRule{}
	for rows.Next() {
		var r fieldRule
		if err := rows.Scan(&r.FieldKey, &r.State, &r.DisplayOrder); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return nil, false
		}
		out = append(out, r)
	}
	return out, true
}

// PublicList — GET /api/registration/field-rules. Returns
// {required: [keys], hidden: [keys]} so a form knows which optional fields
// to enforce and which to not render at all. `required` is kept as the
// existing key name for backward compatibility with the app's current
// fetchRequiredFields() (Note 33 only ADDS the hidden list, doesn't rename
// anything already relied on).
func (h *FieldRulesHandler) PublicList(c *gin.Context) {
	rules, ok := h.list(c)
	if !ok {
		return
	}
	required := []string{}
	hidden := []string{}
	for _, r := range rules {
		switch r.State {
		case "required":
			required = append(required, r.FieldKey)
		case "hidden":
			hidden = append(hidden, r.FieldKey)
		}
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "required": required, "hidden": hidden})
}

// AdminList — GET /api/admin/registration/field-rules (full rows).
func (h *FieldRulesHandler) AdminList(c *gin.Context) {
	rules, ok := h.list(c)
	if !ok {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": rules})
}

// SetState — POST /api/admin/registration/field-rules/:key — body
// {state: "required"|"optional"|"hidden"}.
func (h *FieldRulesHandler) SetState(c *gin.Context) {
	key := strings.TrimSpace(c.Param("key"))
	var req struct {
		State string `json:"state"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	state := strings.TrimSpace(req.State)
	if !inSet(state, fieldRuleStates) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "state must be one of: " + strings.Join(fieldRuleStates, ", ")})
		return
	}
	ct, err := h.Pool.Exec(c.Request.Context(),
		`UPDATE registration_field_rules SET state = $2 WHERE field_key = $1`, key, state)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Unknown field."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "field_key": key, "state": state})
}
