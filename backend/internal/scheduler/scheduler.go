// Package scheduler runs the app's periodic background jobs. Currently that's
// task #20: sponsorship payment-due reminders.
//
// Design notes:
//   - One long-lived goroutine started from main() behind the RUN_SCHEDULER
//     flag. It owns a single ticker and exits cleanly when the passed context
//     is cancelled (the same ctx main() cancels on SIGINT/SIGTERM), so it
//     shuts down with the rest of the process.
//   - Idempotent by construction: sponsorships.DueForReminder only returns
//     rows not yet reminded for their current cycle, and MarkReminded stamps
//     them so the next tick skips them. A crash mid-run just means the
//     unstamped rows get picked up on the next tick — no double-send, no lost
//     reminder.
//   - Best-effort: a single row's failure is logged and the loop continues;
//     it never aborts the whole run or the process.
package scheduler

import (
	"context"
	"log"
	"time"

	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/sponsorships"
)

// bootDelay is how long after startup the first scan runs, so a redeploy
// doesn't fire reminders while the process is still warming up.
const bootDelay = 30 * time.Second

// maxPerRun caps how many reminders one tick sends, so a large backlog is
// drained over several ticks rather than in one burst.
const maxPerRun = 200

type Scheduler struct {
	sponsorships *sponsorships.Store
	notifier     *notify.Notifier
	interval     time.Duration
	daysBefore   int
}

// New builds a Scheduler. interval is how often it scans; daysBefore is the
// look-ahead window for "due soon" reminders.
func New(s *sponsorships.Store, n *notify.Notifier, interval time.Duration, daysBefore int) *Scheduler {
	if interval < time.Minute {
		interval = time.Minute
	}
	return &Scheduler{sponsorships: s, notifier: n, interval: interval, daysBefore: daysBefore}
}

// Start blocks until ctx is cancelled, running the reminder scan once shortly
// after boot and then every interval. Intended to be launched in its own
// goroutine: `go sched.Start(ctx)`.
func (s *Scheduler) Start(ctx context.Context) {
	log.Printf("[scheduler] started (interval=%s, remind %d days ahead)", s.interval, s.daysBefore)

	timer := time.NewTimer(bootDelay)
	defer timer.Stop()

	for {
		select {
		case <-ctx.Done():
			log.Printf("[scheduler] stopped")
			return
		case <-timer.C:
			s.runReminders(ctx)
			timer.Reset(s.interval)
		}
	}
}

// runReminders scans for active sponsorships whose payment is due within the
// window (or overdue) and sends each sponsor a localized reminder, stamping
// the row so it isn't reminded again this cycle.
func (s *Scheduler) runReminders(ctx context.Context) {
	rows, err := s.sponsorships.DueForReminder(ctx, s.daysBefore, maxPerRun)
	if err != nil {
		log.Printf("[scheduler] reminder scan failed: %v", err)
		return
	}
	if len(rows) == 0 {
		return
	}

	sent := 0
	for _, r := range rows {
		if ctx.Err() != nil { // process shutting down mid-run
			return
		}
		dueDate := r.NextDueDate.Format("2006-01-02")
		msg := notify.SponsorshipPaymentDueMsg(r.Amount, r.Currency, r.ProjectTitle, dueDate, r.ID)

		if _, err := s.notifier.Send(ctx, r.DonorUserID, msg); err != nil {
			// Don't stamp on send error — retry on the next tick.
			log.Printf("[scheduler] reminder send failed (sponsorship=%d user=%d): %v", r.ID, r.DonorUserID, err)
			continue
		}
		// Stamp regardless of whether Send deduped (returned 0): the reminder
		// for this cycle is accounted for either way, so we mustn't rescan it.
		if err := s.sponsorships.MarkReminded(ctx, r.ID, r.NextDueDate); err != nil {
			log.Printf("[scheduler] mark-reminded failed (sponsorship=%d): %v", r.ID, err)
			continue
		}
		sent++
	}
	if sent > 0 {
		log.Printf("[scheduler] sent %d sponsorship payment reminder(s)", sent)
	}
}
