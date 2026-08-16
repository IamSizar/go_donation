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
	// Voice — M9's third channel ("تنبيه صوتي ... عند توفره"). Nil in every
	// environment today, which is a supported state and not an error: the
	// sweep logs that the channel is off and carries on. See
	// internal/notify/voice.go for why no provider ships with it.
	Voice notify.VoiceCaller
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
	// M9 — say once per sweep, not once per row, that the voice channel is off.
	// Per-row logging would put a line in the journal for every reminder in
	// every environment, which is how a real warning gets scrolled past.
	voiceOn := notify.VoiceConfigured(h.Voice)
	if !voiceOn && len(items) > 0 {
		log.Printf("[sponsorship-reminders] voice channel not configured; %d reminder(s) go out by in-app%s only",
			len(items), map[bool]string{true: " and SMS", false: ""}[h.SendSMS != nil])
	}

	for _, it := range items {
		amount := strconv.FormatFloat(it.Amount, 'f', -1, 64)

		if it.GrantorUserID != nil {
			if h.Notifier != nil {
				_, _ = h.Notifier.Send(ctx, *it.GrantorUserID,
					notify.SponsorshipDueGrantorMsg(amount, it.Currency, it.DueDate, it.OccurrenceID))
			}
			text := "تذكير: مساهمتك بمبلغ " + amount + " " + it.Currency + " مستحقة بتاريخ " + it.DueDate
			h.sms(ctx, it.GrantorPhone, text)
			h.voice(ctx, voiceOn, it.GrantorPhone, text, it.OccurrenceID)
		}
		if it.RecipientUserID != nil {
			if h.Notifier != nil {
				_, _ = h.Notifier.Send(ctx, *it.RecipientUserID,
					notify.SponsorshipDueRecipientMsg(amount, it.Currency, it.DueDate, it.OccurrenceID))
			}
			text := "تذكير: مساعدتك بمبلغ " + amount + " " + it.Currency + " مقررة بتاريخ " + it.DueDate
			h.sms(ctx, it.RecipientPhone, text)
			h.voice(ctx, voiceOn, it.RecipientPhone, text, it.OccurrenceID)
		}

		// BOTH sides are always closed out, including a side with nobody on it.
		//
		// This is the fix for a forever-loop, and it is the reason the marking
		// moved out of the two `if` blocks above. PendingReminders selects while
		// EITHER stamp is NULL, but a sponsorship with no beneficiary_case_id
		// (the column is nullable) has no recipient user, so the recipient stamp
		// was never written and the occurrence was re-selected on every sweep —
		// re-texting the grantor every six hours for the life of the
		// sponsorship. The in-app leg hid it because notify.Send de-duplicates;
		// the SMS leg has no dedupe, and a voice channel added to the same loop
		// would have placed an automated call on that schedule.
		//
		// "Nobody to remind" is a finished side, not a pending one.
		for _, side := range []string{"grantor", "recipient"} {
			if err := h.Store.MarkReminded(ctx, it.OccurrenceID, side); err != nil {
				log.Printf("[sponsorship-reminders] mark %s %d: %v", side, it.OccurrenceID, err)
			}
		}
	}
}

// voice places the automated call for one recipient, best-effort.
//
// Failures are logged and never returned: a reminder that reached the app and
// the phone must not be re-queued because a call did not connect, and the
// occurrence is marked done either way. voiceOn is passed in so the "channel is
// off" case is decided once per sweep rather than re-tested per row.
func (h *SponsorshipScheduleHandler) voice(ctx context.Context, voiceOn bool, phone, message string, occurrenceID int64) {
	if !voiceOn {
		return
	}
	if strings.TrimSpace(phone) == "" {
		return
	}
	if err := notify.PlaceVoiceCall(ctx, h.Voice, strings.TrimSpace(phone), message); err != nil {
		log.Printf("[sponsorship-reminders] voice call for occurrence %d: %v", occurrenceID, err)
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
