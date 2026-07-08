package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// AidReceiptsHandler powers the digital aid-delivery receipts (#50). Admin
// creates/lists them; the recipient views their own from the app.
type AidReceiptsHandler struct {
	Pool *pgxpool.Pool
}

func NewAidReceiptsHandler(pool *pgxpool.Pool) *AidReceiptsHandler {
	return &AidReceiptsHandler{Pool: pool}
}

type aidReceipt struct {
	ID              int64    `json:"id"`
	ReceiptCode     string   `json:"receipt_code"`
	RecipientUserID *int64   `json:"recipient_user_id"`
	RecipientName   *string  `json:"recipient_name"`
	Items           *string  `json:"items"`
	DeliveredAt     *string  `json:"delivered_at"`
	DeliveredBy     *string  `json:"delivered_by"`
	Photos          []string `json:"photos"`
	Notes           *string  `json:"notes"`
}

func (h *AidReceiptsHandler) scanList(c *gin.Context, where string, args ...any) {
	rows, err := h.Pool.Query(c.Request.Context(),
		`SELECT id, receipt_code, recipient_user_id, recipient_name, items,
		        to_char(delivered_at, 'YYYY-MM-DD'), delivered_by, photos, notes
		   FROM aid_receipts `+where+` ORDER BY id DESC LIMIT 200`, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer rows.Close()
	out := []aidReceipt{}
	for rows.Next() {
		var r aidReceipt
		if err := rows.Scan(&r.ID, &r.ReceiptCode, &r.RecipientUserID, &r.RecipientName, &r.Items,
			&r.DeliveredAt, &r.DeliveredBy, &r.Photos, &r.Notes); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		if r.Photos == nil {
			r.Photos = []string{}
		}
		out = append(out, r)
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": out})
}

// AdminList — GET /api/admin/aid-receipts.
func (h *AidReceiptsHandler) AdminList(c *gin.Context) { h.scanList(c, "") }

// MyList — GET /api/aid-receipts (authed) — the current user's receipts.
func (h *AidReceiptsHandler) MyList(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	h.scanList(c, "WHERE recipient_user_id = $1", user.UserID)
}

type aidReceiptReq struct {
	RecipientUserID *int64   `json:"recipient_user_id"`
	RecipientName   string   `json:"recipient_name"`
	Items           string   `json:"items"`
	DeliveredAt     string   `json:"delivered_at"` // YYYY-MM-DD or ""
	DeliveredBy     string   `json:"delivered_by"`
	Photos          []string `json:"photos"`
	Notes           string   `json:"notes"`
}

// AdminCreate — POST /api/admin/aid-receipts.
func (h *AidReceiptsHandler) AdminCreate(c *gin.Context) {
	var req aidReceiptReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.Photos == nil {
		req.Photos = []string{}
	}
	buf := make([]byte, 3)
	_, _ = rand.Read(buf)
	code := "RCP-" + time.Now().UTC().Format("20060102") + "-" + strings.ToUpper(hex.EncodeToString(buf))

	nilStr := func(s string) any {
		if strings.TrimSpace(s) == "" {
			return nil
		}
		return s
	}

	// Auto-fill the recipient name from the picked user's profile when the admin
	// selected a recipient but left the name blank.
	if strings.TrimSpace(req.RecipientName) == "" && req.RecipientUserID != nil {
		var fn string
		if e := h.Pool.QueryRow(c.Request.Context(),
			`SELECT full_name FROM user_profiles WHERE user_id = $1`, *req.RecipientUserID).Scan(&fn); e == nil {
			req.RecipientName = fn
		}
	}

	// Only accept a valid YYYY-MM-DD date; stray text becomes NULL instead of a
	// DB timestamp error.
	deliveredAt := func() any {
		s := strings.TrimSpace(req.DeliveredAt)
		if s == "" {
			return nil
		}
		if _, e := time.Parse("2006-01-02", s); e != nil {
			return nil
		}
		return s
	}()

	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO aid_receipts (receipt_code, recipient_user_id, recipient_name, items, delivered_at, delivered_by, photos, notes)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
		code, req.RecipientUserID, nilStr(req.RecipientName), nilStr(req.Items),
		deliveredAt, nilStr(req.DeliveredBy), req.Photos, nilStr(req.Notes),
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "receipt_code": code})
}
