package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type HealthHandler struct {
	Pool *pgxpool.Pool
}

func NewHealthHandler(pool *pgxpool.Pool) *HealthHandler {
	return &HealthHandler{Pool: pool}
}

func (h *HealthHandler) Get(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
	defer cancel()

	dbStatus := "up"
	var userCount int
	if err := h.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM users").Scan(&userCount); err != nil {
		dbStatus = "down: " + err.Error()
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":   "degraded",
			"database": dbStatus,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":   "ok",
		"database": dbStatus,
		"users":    userCount,
	})
}
