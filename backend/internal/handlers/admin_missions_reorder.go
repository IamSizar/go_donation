package handlers

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// F7 — reordering قائمة المهام.
//
// The client asked to add a mission, edit one, change its section, and reorder
// the list. The first three were writes to columns that existed; reordering had
// nowhere to write at all until migration 106 added `display_order`. This file
// is the write path for it.
//
// Kept separate from the sibling CMS lists (donation types, payment methods,
// categories) on purpose: those own a whole small table through a Store, while
// missions are a large resource already served by AdminListsHandler /
// AdminCreateHandler / AdminEditHandler. Adding a fifth handler type for one
// column would have been more structure than the change deserves.

// reorderMissions rewrites display_order to match the given id sequence
// (first id → 1, second → 2, …) in a single transaction.
//
// ATOMIC BY DESIGN. Every id must name a real mission; if one does not, the
// whole transaction rolls back and no position moves. A half-applied reorder is
// worse than a refused one — the operator would be looking at a list that
// appears reordered and is not, and the stale ids come from exactly the case
// that causes it (a browser tab open since before someone else deleted a
// mission).
//
// Writes ONE column. Dragging a row is not editing it, so nothing else on the
// mission is touched.
func reorderMissions(ctx context.Context, pool *pgxpool.Pool, orderedIDs []int64) error {
	if pool == nil {
		return errors.New("no database pool")
	}
	if len(orderedIDs) == 0 {
		return nil
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	for i, id := range orderedIDs {
		ct, err := tx.Exec(ctx,
			`UPDATE volunteer_missions SET display_order = $2 WHERE id = $1`, id, i+1)
		if err != nil {
			return fmt.Errorf("reordering mission %d: %w", id, err)
		}
		if ct.RowsAffected() == 0 {
			return fmt.Errorf("mission %d no longer exists; nothing was reordered", id)
		}
	}
	return tx.Commit(ctx)
}

// Reorder handles POST /api/admin/missions/reorder — body {"ids":[3,1,2]}.
//
// Gated by the same `missions edit` permission as PATCH /admin/missions/:id in
// main.go: changing the order staff see is an edit to the list, so it must not
// be reachable by someone who may only view it.
func (h *AdminEditHandler) MissionsReorder(c *gin.Context) {
	var req struct {
		IDs []int64 `json:"ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if err := reorderMissions(c.Request.Context(), h.Pool, req.IDs); err != nil {
		// The message names the mission that broke it, and says plainly that
		// nothing moved, so the operator knows to refresh rather than wonder
		// which half applied.
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}
