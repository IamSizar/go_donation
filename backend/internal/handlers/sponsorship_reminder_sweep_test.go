// sponsorship_reminder_sweep_test.go — M9: does the reminder sweep tell each
// side once, and can a third channel be added to it safely?
//
// # WHAT THE REPORT SAID, AND WHAT IS ACTUALLY THERE
//
// VERIFICATION_REPORT said donor AND beneficiary are both reminded and only the
// VOICE channel is missing. The first half is true — RunReminderSweep does send
// to both — but the sweep had a defect that made adding a third channel unsafe,
// and it is pinned here before anything is added on top of it.
//
// THE DEFECT: PendingReminders selects while
// `reminded_grantor_at IS NULL OR reminded_recipient_at IS NULL`, but the sweep
// only stamps a side when that side HAS A USER. A sponsorship with no
// beneficiary_case_id (the column is nullable) therefore never gets
// reminded_recipient_at stamped, so the row is re-selected on EVERY sweep,
// forever. The in-app leg hides this because notify.Send de-duplicates; the SMS
// leg has no dedupe at all, so the donor is texted every six hours until the
// sponsorship ends.
//
// That is dormant only because OTPIQ_API_KEY is unset in every environment
// today — the SMS closure in main.go returns nil for a message it never sent.
// The moment the credential lands, which is exactly what M9 asks for, it
// becomes a live spam incident. A voice channel added to the same loop would
// have made it an automated call every six hours.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_m9?sslmode=disable' \
//	  go test ./internal/handlers/ -run ReminderSweep -v
package handlers

import (
	"context"
	"fmt"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/appsettings"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/sponsorshipschedule"
)

// ─── Harness ────────────────────────────────────────────────────────────

// recordingChannel stands in for a real gateway and simply counts what it was
// asked to send, so "was this sent twice?" is answerable.
type recordingChannel struct {
	mu    sync.Mutex
	calls []string
}

func (r *recordingChannel) record(phone string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls = append(r.calls, phone)
}

func (r *recordingChannel) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.calls)
}

// makeSponsorshipDueToday inserts a donor, a sponsorship with NO
// beneficiary_case_id — the shape that triggers the defect — and one schedule
// occurrence due today. Everything is removed afterwards.
func makeSponsorshipDueToday(t *testing.T, pool *pgxpool.Pool) (donorID int64, occurrenceID int64) {
	t.Helper()
	ctx := context.Background()
	donorID = makeContactUser(t, pool, "user")

	var sponsorshipID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO sponsorships (donor_user_id, beneficiary_case_id, sponsorship_type,
		                           amount, currency, schedule_interval, next_due_date, status)
		 VALUES ($1, NULL, 'project', 100000.00, 'IQD', 'monthly', CURRENT_DATE, 'active')
		 RETURNING id`, donorID,
	).Scan(&sponsorshipID); err != nil {
		t.Fatalf("insert sponsorship: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM sponsorship_schedule WHERE sponsorship_id = $1`, sponsorshipID)
		_, _ = pool.Exec(ctx, `DELETE FROM sponsorships WHERE id = $1`, sponsorshipID)
	})

	if err := pool.QueryRow(ctx,
		`INSERT INTO sponsorship_schedule (sponsorship_id, due_date, amount, currency, status)
		 VALUES ($1, CURRENT_DATE, 100000.00, 'IQD', 'due') RETURNING id`, sponsorshipID,
	).Scan(&occurrenceID); err != nil {
		t.Fatalf("insert schedule occurrence: %v", err)
	}
	return donorID, occurrenceID
}

func newSweepHandler(pool *pgxpool.Pool) *SponsorshipScheduleHandler {
	return NewSponsorshipScheduleHandler(
		sponsorshipschedule.New(pool), appsettings.New(pool), notify.New(pool))
}

// ─── The defect ─────────────────────────────────────────────────────────

// TestReminderSweep_TellsEachSideOnlyOnce is the regression test for the
// forever-loop. Two sweeps, one occurrence, one reachable side: the donor must
// hear about it exactly once.
func TestReminderSweep_TellsEachSideOnlyOnce(t *testing.T) {
	pool := newContactBlockPool(t)
	_, occurrenceID := makeSponsorshipDueToday(t, pool)

	sms := &recordingChannel{}
	h := newSweepHandler(pool)
	h.SendSMS = func(ctx context.Context, phone, message string) error {
		sms.record(phone)
		return nil
	}

	ctx := context.Background()
	h.RunReminderSweep(ctx)
	afterFirst := sms.count()
	h.RunReminderSweep(ctx) // the loop: a second sweep must find nothing to do
	afterSecond := sms.count()

	if afterFirst != 1 {
		t.Fatalf("first sweep sent %d SMS, want 1", afterFirst)
	}
	if afterSecond != 1 {
		t.Fatalf("second sweep sent %d SMS in total, want 1 — the occurrence is being re-selected forever", afterSecond)
	}

	// And the row must no longer be pending on EITHER side, or the next sweep
	// picks it up again.
	var grantorStamped, recipientStamped bool
	if err := pool.QueryRow(ctx,
		`SELECT reminded_grantor_at IS NOT NULL, reminded_recipient_at IS NOT NULL
		   FROM sponsorship_schedule WHERE id = $1`, occurrenceID,
	).Scan(&grantorStamped, &recipientStamped); err != nil {
		t.Fatalf("read stamps: %v", err)
	}
	if !grantorStamped {
		t.Fatal("reminded_grantor_at not stamped")
	}
	if !recipientStamped {
		t.Fatal("reminded_recipient_at not stamped — there is nobody on that side to remind, so it must be closed out, not retried forever")
	}
}

// ─── The voice channel (M9's actual ask) ────────────────────────────────

// TestReminderSweep_PlacesVoiceCallWhenProviderConfigured pins the hook. No
// provider is invented here — the test supplies one, which is the whole point:
// the sweep must call whatever is wired without knowing who it is.
func TestReminderSweep_PlacesVoiceCallWhenProviderConfigured(t *testing.T) {
	pool := newContactBlockPool(t)
	makeSponsorshipDueToday(t, pool)

	voice := &recordingChannel{}
	h := newSweepHandler(pool)
	h.Voice = notify.VoiceCallerFunc(func(ctx context.Context, phone, message string) error {
		voice.record(phone)
		return nil
	})

	h.RunReminderSweep(context.Background())

	if got := voice.count(); got != 1 {
		t.Fatalf("voice calls = %d, want 1 — the reminder sweep must drive the voice channel too", got)
	}
}

// The failure mode this product has already been bitten by: a channel that
// reports success for a message it never sent. main.go's SMS closure returns
// nil when OTPIQ is unconfigured, which is why nobody noticed the SMS leg has
// never worked. The voice channel must not repeat it.
func TestReminderSweep_UnconfiguredVoiceIsNotSilentSuccess(t *testing.T) {
	if err := notify.PlaceVoiceCall(context.Background(), nil, "9647701234567", "test"); err == nil {
		t.Fatal("an unconfigured voice channel reported success; it must report ErrVoiceNotConfigured")
	}
	var nilCaller notify.VoiceCaller
	if notify.VoiceConfigured(nilCaller) {
		t.Fatal("VoiceConfigured reported true for a nil provider")
	}
}

// A sweep with no voice provider — every environment today — must still do all
// of its other work. The voice channel is additive, never a gate.
func TestReminderSweep_RunsFineWithNoVoiceProvider(t *testing.T) {
	pool := newContactBlockPool(t)
	makeSponsorshipDueToday(t, pool)

	sms := &recordingChannel{}
	h := newSweepHandler(pool) // h.Voice deliberately left nil
	h.SendSMS = func(ctx context.Context, phone, message string) error {
		sms.record(phone)
		return nil
	}

	h.RunReminderSweep(context.Background())

	if got := sms.count(); got != 1 {
		t.Fatalf("SMS sent = %d, want 1 — a missing voice provider must not stop the other channels", got)
	}
	_ = fmt.Sprint() // keep fmt imported for the helper above
}
