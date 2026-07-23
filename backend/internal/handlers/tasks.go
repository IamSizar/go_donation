package handlers

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/tasks"
)

// TasksHandler — client note "Task Verification": staff assign a task to a
// user, who sees it in their own list and marks it done themselves.
type TasksHandler struct {
	Tasks    *tasks.Store
	Notifier *notify.Notifier
}

func NewTasksHandler(t *tasks.Store, n *notify.Notifier) *TasksHandler {
	return &TasksHandler{Tasks: t, Notifier: n}
}

// GET /api/tasks — the current user's own assigned tasks.
func (h *TasksHandler) ListMine(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Unauthorized."})
		return
	}
	items, err := h.Tasks.ListForUser(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to load tasks."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "success", "tasks": items})
}

// POST /api/tasks/:id/complete — the current user marks their own task done.
func (h *TasksHandler) Complete(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Unauthorized."})
		return
	}
	taskID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || taskID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid task id."})
		return
	}
	if err := h.Tasks.Complete(c.Request.Context(), taskID, user.UserID); err != nil {
		if errors.Is(err, tasks.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"status": "error", "error": "Task not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to complete task."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "success"})
}

// GET /api/admin/tasks — all tasks (optionally filtered by ?user_id=), for
// the admin dashboard's Tasks page.
func (h *TasksHandler) AdminList(c *gin.Context) {
	userID, _ := strconv.ParseInt(c.Query("user_id"), 10, 64)
	page, _ := strconv.Atoi(c.Query("page"))
	perPage, _ := strconv.Atoi(c.Query("per_page"))
	items, err := h.Tasks.AdminList(c.Request.Context(), userID, page, perPage)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to load tasks."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "success", "tasks": items})
}

type adminCreateTaskReq struct {
	UserID      int64  `json:"user_id"`
	Title       string `json:"title"`
	Description string `json:"description"`
}

// POST /api/admin/tasks — assign a new task to a user; notifies them.
func (h *TasksHandler) AdminCreate(c *gin.Context) {
	var req adminCreateTaskReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid request body."})
		return
	}
	if req.UserID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "user_id is required."})
		return
	}

	admin, _ := auth.UserFromGin(c)
	var adminID int64
	if admin != nil {
		adminID = admin.UserID
	}

	task, err := h.Tasks.AdminCreate(c.Request.Context(), req.UserID, req.Title, req.Description, adminID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": err.Error()})
		return
	}

	if h.Notifier != nil {
		title, targetID := task.Title, task.UserID
		go func() {
			bg, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			if _, err := h.Notifier.Send(bg, targetID, notify.TaskAssignedMsg(title)); err != nil {
				log.Printf("[notify] task assigned alert failed: %v", err)
			}
		}()
	}

	c.JSON(http.StatusOK, gin.H{"status": "success", "task": task})
}

// DELETE /api/admin/tasks/:id — an admin correcting a mis-assignment.
func (h *TasksHandler) AdminDelete(c *gin.Context) {
	taskID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || taskID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid task id."})
		return
	}
	if err := h.Tasks.AdminDelete(c.Request.Context(), taskID); err != nil {
		if errors.Is(err, tasks.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"status": "error", "error": "Task not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to delete task."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "success"})
}
