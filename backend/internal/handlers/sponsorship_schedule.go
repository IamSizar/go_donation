package handlers

import (
	"context"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/appsettings"
	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/sponsorshipschedule"
)

// SponsorshipScheduleHandler serves "Eighth: Sponsorship Schedule and
// Calendar" — the entitlement-tracking screen plus the reminder sweep.
type SponsorshipScheduleHandler struct {
	Store    *sponsorshipschedule.Store
	Settings *appsettings.Store
	Notifier *notify.Notifier
	// SendSMS is the same best-effort sender the donation alerts use. Nil
	// disables the SMS leg; in-app notifications still go out.
	SendSMS func(ctx context.Context, phone, message string) error
}

func NewSponsorshipScheduleHandler(
	s *sponsorshipschedule.Store,
	set *appsettings.Store,
	n *notify.Notifier,
) *SponsorshipScheduleHandler {
	return &SponsorshipScheduleHandler{Store: s, Settings: set, Notifier: n}
}

// GET /api/sponsorships/schedule?status=upcoming|due|overdue|paid|skipped
// The tracking screen: upcoming contributions, assistance due now, overdue
// items, and past history — scoped to the caller as grantor or recipient.
func (h *SponsorshipScheduleHandler) List(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	// Keep statuses honest before reading them.
	if _, err := h.Store.RefreshStatuses(c.Request.Context()); err != nil {
		log.Printf("[sponsorship-schedule] refresh: %v", err)
	}
	status := strings.TrimSpace(c.Query("status"))
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	items, err := h.Store.List(c.Request.Context(), user.UserID, status, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// POST /api/admin/sponsorships/:id/schedule/generate — materialise (or top up)
// a sponsorship's schedule. Idempotent.
func (h *SponsorshipScheduleHandler) Generate(c *gin.Context) {
	id, _ := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid sponsorship id."})
		return
	}
	count, _ := strconv.Atoi(strings.TrimSpace(c.Query("count")))
	created, err := h.Store.Generate(c.Request.Context(), id, count)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "created": created})
}

// POST /api/admin/sponsorships/schedule/:occurrenceId/paid — settle one date.
func (h *SponsorshipScheduleHandler) MarkPaid(c *gin.Context) {
	id, _ := strconv.ParseInt(strings.TrimSpace(c.Param("occurrenceId")), 10, 64)
	if id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid occurrence id."})
		return
	}
	if err := h.Store.MarkPaid(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// RunReminderSweep notifies both sides about dates coming due: an in-app
// notification always, plus an SMS when a phone is known and the sender is
// wired. Each side is marked so it is never told twice for the same date.
//
// Safe to call on a timer and safe to call concurrently with itself — the
// reminded_* columns are the guard.
func (h *SponsorshipScheduleHandler) RunReminderSweep(ctx context.Context) {
	days := 3
	if h.Settings != nil {
		if v, err := h.Settings.Get(ctx, "sponsorship_reminder_days_before"); err == nil {
			if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && n >= 0 {
				days = n
			}
		}
	}
	items, err := h.Store.PendingReminders(ctx, days)
	if err != nil {
		log.Printf("[sponsorship-reminders] query: %v", err)
		return
	}
	for _, it := range items {
		amount := strconv.FormatFloat(it.Amount, 'f', -1, 64)

		if it.GrantorUserID != nil {
			if h.Notifier != nil {
				_, _ = h.Notifier.Send(ctx, *it.GrantorUserID,
					notify.SponsorshipDueGrantorMsg(amount, it.Currency, it.DueDate, it.OccurrenceID))
			}
			h.sms(ctx, it.GrantorPhone,
				"تذكير: مساهمتك بمبلغ "+amount+" "+it.Currency+" مستحقة بتاريخ "+it.DueDate)
			if err := h.Store.MarkReminded(ctx, it.OccurrenceID, "grantor"); err != nil {
				log.Printf("[sponsorship-reminders] mark grantor %d: %v", it.OccurrenceID, err)
			}
		}
		if it.RecipientUserID != nil {
			if h.Notifier != nil {
				_, _ = h.Notifier.Send(ctx, *it.RecipientUserID,
					notify.SponsorshipDueRecipientMsg(amount, it.Currency, it.DueDate, it.OccurrenceID))
			}
			h.sms(ctx, it.RecipientPhone,
				"تذكير: مساعدتك بمبلغ "+amount+" "+it.Currency+" مقررة بتاريخ "+it.DueDate)
			if err := h.Store.MarkReminded(ctx, it.OccurrenceID, "recipient"); err != nil {
				log.Printf("[sponsorship-reminders] mark recipient %d: %v", it.OccurrenceID, err)
			}
		}
	}
}

func (h *SponsorshipScheduleHandler) sms(ctx context.Context, phone, message string) {
	if h.SendSMS == nil {
		return
	}
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return
	}
	if err := h.SendSMS(ctx, phone, message); err != nil {
		log.Printf("[sponsorship-reminders] sms: %v", err)
	}
}

// StartReminderLoop runs the sweep once at startup and then on a ticker.
func (h *SponsorshipScheduleHandler) StartReminderLoop(every time.Duration) {
	if every <= 0 {
		every = 6 * time.Hour
	}
	go func() {
		for {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			h.RunReminderSweep(ctx)
			cancel()
			time.Sleep(every)
		}
	}()
}
