// admin_status_notify_sponsorship_lang_test.go — approving a sponsorship must
// push a body that names the project in the recipient's own language.
//
// Client feedback round 1: notifySponsorshipDecision selected
// COALESCE(pr.project_title, bc.public_title, ”) — the ENGLISH column only —
// even though project_title_ar / _sorani / _badini (and the beneficiary_cases
// public_title_* twins) exist. Every language therefore got the English title
// embedded in its sentence.
//
// Integration test against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set.
package handlers

import (
	"context"
	"fmt"
	"math/rand"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// sponsorshipNotifyFixture is one donor + one sponsorship pointing at a source
// row whose title exists in all four languages.
type sponsorshipNotifyFixture struct {
	donorID       int64
	sponsorshipID int64
	titles        notify.LocalText
}

// seedProjectRequestSponsorship builds the common shape: a sponsorship on a
// beneficiary_project_requests row with all four project_title columns filled.
func seedProjectRequestSponsorship(t *testing.T, pool *pgxpool.Pool) sponsorshipNotifyFixture {
	t.Helper()
	ctx := context.Background()
	donor := makeDupProfilesUser(t, pool)

	suffix := rand.Intn(100000000)
	titles := notify.LocalText{
		En:  fmt.Sprintf("Winter Relief %d", suffix),
		Ar:  fmt.Sprintf("إغاثة الشتاء %d", suffix),
		Ckb: fmt.Sprintf("یارمەتیی زستان %d", suffix),
		Kmr: fmt.Sprintf("هاریکاریا زڤستانێ %d", suffix),
	}

	var requestID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_project_requests
		   (user_id, project_title, project_title_ar, project_title_sorani, project_title_badini,
		    category, summary, description_long, amount_needed, location, beneficiary_community_name, status)
		 VALUES ($1, $2, $3, $4, $5, 'relief', 'summary', 'description', 1000, 'Erbil', 'Test Community', 'approved')
		 RETURNING id`,
		donor, titles.En, titles.Ar, titles.Ckb, titles.Kmr,
	).Scan(&requestID); err != nil {
		t.Fatalf("insert project request: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_project_requests WHERE id = $1`, requestID)
	})

	var sponsorshipID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO sponsorships (donor_user_id, project_request_id, sponsorship_type, amount, currency, status)
		 VALUES ($1, $2, 'monthly', 50000, 'IQD', 'pending') RETURNING id`,
		donor, requestID,
	).Scan(&sponsorshipID); err != nil {
		t.Fatalf("insert sponsorship: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM sponsorships WHERE id = $1`, sponsorshipID)
	})

	return sponsorshipNotifyFixture{donorID: donor, sponsorshipID: sponsorshipID, titles: titles}
}

// latestSponsorshipNotification reads back the four body columns of the most
// recent notification written for this donor about this sponsorship.
func latestSponsorshipNotification(t *testing.T, pool *pgxpool.Pool, f sponsorshipNotifyFixture) notify.LocalText {
	t.Helper()
	var body notify.LocalText
	var ar, ckb, kmr *string
	if err := pool.QueryRow(context.Background(),
		`SELECT body, body_ar, body_sorani, body_badini
		   FROM app_notifications
		  WHERE user_id = $1 AND related_entity_type = 'sponsorships' AND related_entity_id = $2
		  ORDER BY id DESC LIMIT 1`,
		f.donorID, f.sponsorshipID,
	).Scan(&body.En, &ar, &ckb, &kmr); err != nil {
		t.Fatalf("read notification: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM app_notifications WHERE user_id = $1`, f.donorID)
	})
	deref := func(p *string) string {
		if p == nil {
			return ""
		}
		return *p
	}
	body.Ar, body.Ckb, body.Kmr = deref(ar), deref(ckb), deref(kmr)
	return body
}

func TestSponsorshipAcceptedPushNamesTheProjectInEachLanguage(t *testing.T) {
	pool := newDupProfilesPool(t)
	f := seedProjectRequestSponsorship(t, pool)

	h := &AdminStatusHandler{Pool: pool, Notifier: &notify.Notifier{Pool: pool}}
	h.notifySponsorshipDecision(context.Background(), f.sponsorshipID, "active")

	body := latestSponsorshipNotification(t, pool, f)
	for _, tc := range []struct{ lang, got, want string }{
		{"En", body.En, f.titles.En},
		{"Ar", body.Ar, f.titles.Ar},
		{"Ckb", body.Ckb, f.titles.Ckb},
		{"Kmr", body.Kmr, f.titles.Kmr},
	} {
		if !strings.Contains(tc.got, tc.want) {
			t.Errorf("%s body does not name the project in %s: got %q, want it to contain %q",
				tc.lang, tc.lang, tc.got, tc.want)
		}
	}
	for _, tc := range []struct{ lang, got string }{{"Ar", body.Ar}, {"Ckb", body.Ckb}, {"Kmr", body.Kmr}} {
		if strings.Contains(tc.got, f.titles.En) {
			t.Errorf("%s body carries the ENGLISH project title: %q", tc.lang, tc.got)
		}
	}
}

// TestSponsorshipAcceptedPushFallsBackToEnglishTitle covers the far more common
// real row: only project_title is filled. Every language must still name the
// project (in English, the only text there is) rather than degrade to the
// "General support" sentence.
func TestSponsorshipAcceptedPushFallsBackToEnglishTitle(t *testing.T) {
	pool := newDupProfilesPool(t)
	ctx := context.Background()
	donor := makeDupProfilesUser(t, pool)
	title := fmt.Sprintf("English Only Project %d", rand.Intn(100000000))

	var requestID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_project_requests
		   (user_id, project_title, category, summary, description_long, amount_needed, location, beneficiary_community_name, status)
		 VALUES ($1, $2, 'relief', 'summary', 'description', 1000, 'Erbil', 'Test Community', 'approved') RETURNING id`,
		donor, title,
	).Scan(&requestID); err != nil {
		t.Fatalf("insert project request: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_project_requests WHERE id = $1`, requestID)
	})
	var sponsorshipID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO sponsorships (donor_user_id, project_request_id, sponsorship_type, amount, currency, status)
		 VALUES ($1, $2, 'monthly', 50000, 'IQD', 'pending') RETURNING id`,
		donor, requestID,
	).Scan(&sponsorshipID); err != nil {
		t.Fatalf("insert sponsorship: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM sponsorships WHERE id = $1`, sponsorshipID)
	})

	h := &AdminStatusHandler{Pool: pool, Notifier: &notify.Notifier{Pool: pool}}
	h.notifySponsorshipDecision(ctx, sponsorshipID, "active")

	f := sponsorshipNotifyFixture{donorID: donor, sponsorshipID: sponsorshipID}
	body := latestSponsorshipNotification(t, pool, f)
	for lang, got := range map[string]string{"En": body.En, "Ar": body.Ar, "Ckb": body.Ckb, "Kmr": body.Kmr} {
		if !strings.Contains(got, title) {
			t.Errorf("%s body does not name the project: %q", lang, got)
		}
	}
}
