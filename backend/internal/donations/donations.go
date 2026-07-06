package donations

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/sectioncodes"
)

func itoa(n int) string { return strconv.Itoa(n) }

// normalizeDonationType maps a donor-supplied donation type to a known value
// (general / zakat / sadaqah), defaulting to general (#16).
func normalizeDonationType(t string) string {
	switch strings.ToLower(strings.TrimSpace(t)) {
	case "zakat":
		return "zakat"
	case "sadaqah", "sadaqa":
		return "sadaqah"
	default:
		return "general"
	}
}

// Lifecycle-gate errors returned from Insert. Handlers should translate these
// to user-facing 400 / 410 responses rather than 500.
var (
	ErrCampaignNotFound     = errors.New("campaign not found")
	ErrCampaignFinished     = errors.New("campaign has finished and is no longer accepting donations")
	ErrCampaignNotDonatable = errors.New("campaign is not accepting donations right now")
)

// Donation is the row returned to clients (mirrors getDonationsByUserId shape).
type Donation struct {
	ID              int64   `json:"id"`
	ReferenceNumber *string `json:"reference_number"`
	UserID          int64   `json:"user_id"`
	CampaignID      *int64  `json:"campaign_id"`
	DonationKind    string  `json:"donation_kind"`
	CampaignName    *string `json:"campaign_name"`
	CampaignNameAr  *string `json:"campaign_name_ar"`
	Currency        string  `json:"currency"`
	Message         string  `json:"message"`
	Amount          string  `json:"amount"`
	PaymentStatus   int     `json:"payment_status"`
	DeliveryStatus  string  `json:"delivery_status"`
	PaymentMethod   string  `json:"payment_method"`
	ImpactNote      *string `json:"impact_note"`
	TransactionDate time.Time `json:"transaction_date"`
}

// Stats mirrors the PHP "stats" object on /my_donations.
type Stats struct {
	TotalCount    int    `json:"total_count"`
	TotalAmount   string `json:"total_amount"`
	SuccessCount  int    `json:"success_count"`
	SuccessAmount string `json:"success_amount"`
	PendingCount  int    `json:"pending_count"`
	PendingAmount string `json:"pending_amount"`
	FailedCount   int    `json:"failed_count"`
	FailedAmount  string `json:"failed_amount"`
}

// InsertedDonation is the small shape returned in the /donate response.
type InsertedDonation struct {
	ID              int64  `json:"id"`
	ReferenceNumber string `json:"reference_number"`
	UserID          int64  `json:"user_id"`
	CampaignID      *int64 `json:"campaign_id"`
	DonationKind    string `json:"donation_kind"`
	DonationType    string `json:"donation_type"`
}

type Store struct {
	Pool *pgxpool.Pool
	// Codes issues per-section transaction-code namespaces (#14). Optional: when
	// nil (or the kind has no config row), Insert falls back to the legacy
	// DON-YYYYMMDD-HEX reference.
	Codes *sectioncodes.Store
	// SendSMS sends a best-effort operational SMS (#15 donation-arrived alert).
	// Optional: when nil, no SMS is sent. Kept as a func so this package doesn't
	// depend on the SMS-provider package.
	SendSMS func(ctx context.Context, phone, message string) error
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{Pool: pool}
}

// Insert ports insertDonationUserId(). Validates inputs the same way and
// returns the inserted-donation metadata.
func (s *Store) Insert(
	ctx context.Context,
	userID int64,
	campaignID *int64,
	message *string,
	amount *string,
	paymentMethod *string,
	donationType string,
) (*InsertedDonation, error) {
	if userID <= 0 {
		return nil, errors.New("invalid userID")
	}
	if campaignID != nil && *campaignID <= 0 {
		campaignID = nil
	}

	msg := ""
	if message != nil {
		msg = strings.TrimSpace(*message)
		if utf8.RuneCountInString(msg) > 500 {
			msg = string([]rune(msg)[:500])
		}
	}

	var amountStr string
	if amount != nil {
		amt := strings.TrimSpace(*amount)
		var n float64
		if _, err := fmt.Sscanf(amt, "%f", &n); err == nil && n > 0 && n < 1_000_000 {
			amountStr = amt
		}
	}

	method := ""
	if paymentMethod != nil {
		method = strings.TrimSpace(*paymentMethod)
		if utf8.RuneCountInString(method) > 64 {
			method = string([]rune(method)[:64])
		}
	}

	donationKind := "campaign"
	if campaignID == nil {
		donationKind = "general"
	}

	// #16 — the donor-facing giving type (general/zakat/sadaqah), orthogonal to
	// the internal donation_kind routing. Normalized to a known value.
	dType := normalizeDonationType(donationType)

	// Phase 15 — the INSERT and the campaign roll-up have to land atomically
	// so the donor never sees a donation row without the matching bump in
	// `campaigns.raised_amount`. We use a single transaction; both columns
	// (donations.amount and campaigns.raised_amount) are VARCHAR for legacy
	// PHP compatibility, so we cast through ::numeric in the UPDATE.
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	// Best-effort rollback; the happy path commits below.
	defer func() { _ = tx.Rollback(ctx) }()

	// Phase 15.1 — campaign lifecycle gate. Reject the donation when the
	// referenced campaign is hidden or finished (or missing entirely). This
	// runs inside the tx so we don't race against an admin retiring the
	// campaign mid-checkout.
	if campaignID != nil {
		var status string
		err := tx.QueryRow(ctx,
			`SELECT status FROM campaigns WHERE id = $1`,
			*campaignID,
		).Scan(&status)
		switch {
		case errors.Is(err, pgx.ErrNoRows):
			return nil, ErrCampaignNotFound
		case err != nil:
			return nil, err
		case status == "finished":
			return nil, ErrCampaignFinished
		case status != "active":
			// "hidden" or any unexpected value — donor shouldn't have
			// reached this point anyway, so treat the same as not-found.
			return nil, ErrCampaignNotDonatable
		}
	}

	// #14 — issue this section's next namespaced reference inside the tx, so a
	// rolled-back donation doesn't leave a gap in the sequence. Falls back to the
	// legacy DON-YYYYMMDD-HEX code when no namespace is configured for the kind.
	refNumber, err := s.nextReference(ctx, tx, donationKind)
	if err != nil {
		return nil, err
	}

	var newID int64
	if err := tx.QueryRow(ctx, `
		INSERT INTO donations
		   (reference_number, user_id, campaign_id, donation_kind, donation_type, message, amount, payment_method)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id`,
		refNumber, userID, campaignID, donationKind, dType, msg, amountStr, method,
	).Scan(&newID); err != nil {
		return nil, err
	}

	// NOTE: a brand-new donation lands as delivery_status='registered'
	// (pending admin review), so it deliberately does NOT bump the campaign's
	// raised_amount yet. The amount only starts counting once the admin
	// confirms it (delivery_status -> 'received'/'delivered'), at which point
	// handlers.recalcCampaignRaised recomputes the campaign total from its
	// confirmed donations. This is what stops a campaign from showing money it
	// hasn't actually collected.

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	// #15 — best-effort: SMS the section's contact that a donation arrived. Runs
	// detached with its own timeout so a slow/absent SMS provider never affects
	// the donor response, and a send failure never fails the donation.
	s.notifySectionArrival(donationKind, amountStr, refNumber)

	return &InsertedDonation{
		ID:              newID,
		ReferenceNumber: refNumber,
		UserID:          userID,
		CampaignID:      campaignID,
		DonationKind:    donationKind,
		DonationType:    dType,
	}, nil
}

// notifySectionArrival fires a best-effort SMS to a section's configured contact
// after a donation commits (#15). No-op when SMS isn't wired, the section has no
// phone, or notifications are disabled for it.
func (s *Store) notifySectionArrival(kind, amount, reference string) {
	if s.SendSMS == nil || s.Codes == nil {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		phone, enabled, ok, err := s.Codes.GetNotify(ctx, kind)
		if err != nil || !ok || !enabled {
			return
		}
		phone = strings.TrimSpace(phone)
		if phone == "" {
			return
		}
		if err := s.SendSMS(ctx, phone, arrivalSMS(kind, amount, reference)); err != nil {
			log.Printf("[donation-sms] section=%s ref=%s: %v", kind, reference, err)
		}
	}()
}

// arrivalSMS builds the Arabic donation-arrived alert for a section contact.
func arrivalSMS(kind, amount, reference string) string {
	amt := strings.TrimSpace(amount)
	if amt == "" {
		amt = "—"
	}
	return fmt.Sprintf("مساهمة جديدة (%s): %s د.ع — الرمز: %s", sectionLabelAr(kind), amt, reference)
}

// sectionLabelAr maps a donation_kind to its Arabic section label for SMS.
func sectionLabelAr(kind string) string {
	switch kind {
	case "general":
		return "عام"
	case "campaign":
		return "حملة"
	case "sponsorship":
		return "كفالة"
	case "in_kind":
		return "عيني"
	case "operational":
		return "تشغيلي"
	default:
		return kind
	}
}

// nextReference returns the next namespaced code for kind (e.g. CAM-000042),
// falling back to the legacy DON-YYYYMMDD-HEX format when no namespace store is
// wired or the kind has no config row. Pass the donation's tx as q so a
// consumed number rolls back with a failed donation.
func (s *Store) nextReference(ctx context.Context, q sectioncodes.Querier, kind string) (string, error) {
	if s.Codes != nil {
		code, ok, err := s.Codes.NextReference(ctx, q, kind)
		if err != nil {
			return "", err
		}
		if ok {
			return code, nil
		}
	}
	refHex, err := randHex(4)
	if err != nil {
		return "", err
	}
	return "DON-" + time.Now().UTC().Format("20060102") + "-" + strings.ToUpper(refHex), nil
}

// CancelByDonor lets a donor cancel their own donation when it's still in
// an early lifecycle state. Mirrors a self-service "I made a mistake"
// flow without admin involvement.
//
// Phase 23. Rules:
//   • Donation must belong to userID (the bearer token's user)
//   • Current delivery_status must be 'registered' (still pending review)
//     — once admin has 'received' or 'delivered' it, the donor can no
//     longer rescind; they have to contact support.
//   • Side effects on success:
//       - delivery_status = 'cancelled'
//       - campaigns.raised_amount -= donation.amount
//         (mirrors the +amount bump in Insert; net zero)
//
// All of the above runs in a single transaction so a partial state can't
// land in the DB.
//
// Sentinel errors let the handler emit appropriate HTTP codes:
var (
	ErrDonationNotFound       = errors.New("donation not found")
	ErrDonationNotOwned       = errors.New("you can only cancel your own donations")
	ErrDonationNotCancellable = errors.New("this donation can no longer be cancelled (already received or delivered)")
)

// CancelByDonor returns the donation's amount + campaign_id so the caller
// can fire a confirmation notification if desired.
func (s *Store) CancelByDonor(ctx context.Context, donationID, userID int64) (amount string, campaignID *int64, err error) {
	if donationID <= 0 || userID <= 0 {
		return "", nil, ErrDonationNotFound
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return "", nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var ownerID int64
	var deliveryStatus string
	var amt string
	var cid *int64
	err = tx.QueryRow(ctx,
		`SELECT user_id, delivery_status, amount, campaign_id
		   FROM donations WHERE id = $1`,
		donationID,
	).Scan(&ownerID, &deliveryStatus, &amt, &cid)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return "", nil, ErrDonationNotFound
	case err != nil:
		return "", nil, err
	}
	if ownerID != userID {
		return "", nil, ErrDonationNotOwned
	}
	// Only allow self-cancel for "registered" — anything further into the
	// pipeline is admin's call. ('cancelled' is also a no-op safeguard.)
	if deliveryStatus != "registered" {
		return "", nil, ErrDonationNotCancellable
	}

	if _, err := tx.Exec(ctx,
		`UPDATE donations SET delivery_status = 'cancelled' WHERE id = $1`,
		donationID,
	); err != nil {
		return "", nil, err
	}

	// No raised_amount adjustment needed here: self-cancel is only allowed
	// while the donation is still 'registered' (pending), and pending
	// donations were never counted toward raised_amount in the first place.
	// (Confirmed donations are reversed by the admin status flow, which
	// re-derives the campaign total via handlers.recalcCampaignRaised.)

	if err := tx.Commit(ctx); err != nil {
		return "", nil, err
	}
	return amt, cid, nil
}

// ListByUser ports getDonationsByUserId(). Returns the list + summary stats.
// "general" donations get a synthetic campaign name like the PHP version.
func (s *Store) ListByUser(ctx context.Context, userID int64) ([]Donation, Stats, error) {
	emptyStats := Stats{
		TotalAmount:   "0",
		SuccessAmount: "0",
		PendingAmount: "0",
		FailedAmount:  "0",
	}
	if userID <= 0 {
		return nil, emptyStats, errors.New("invalid userID")
	}

	// Phase 18c — donations.campaign_id is a FK to the `campaigns` table
	// (since Phase 15 unified donor + admin on the campaigns table). This
	// join was historically pointing at `beneficiary_project_requests`,
	// which shares ids 1 and 2 with the campaigns table — so donations to
	// campaign id=1 ("Winter Relief") were displayed as project id=1
	// ("Solar Panels for Off-Grid Village School"). Fixed to join campaigns
	// and pull title / title_ar from there. Campaigns has no currency
	// column today; we hardcode IQD which is what every campaign uses.
	rows, err := s.Pool.Query(ctx, `
		SELECT d.id, d.reference_number, d.user_id, d.campaign_id, d.donation_kind,
		       c.title, c.title_ar,
		       'IQD'::text AS currency,
		       d.message, d.amount, d.payment_status, d.delivery_status,
		       d.payment_method, d.impact_note, d.transaction_date
		  FROM donations d
		  LEFT JOIN campaigns c ON d.campaign_id = c.id
		 WHERE d.user_id = $1
		 ORDER BY d.transaction_date DESC, d.id DESC`,
		userID,
	)
	if err != nil {
		return nil, emptyStats, err
	}
	defer rows.Close()

	items := []Donation{}
	for rows.Next() {
		var d Donation
		err := rows.Scan(
			&d.ID, &d.ReferenceNumber, &d.UserID, &d.CampaignID, &d.DonationKind,
			&d.CampaignName, &d.CampaignNameAr, &d.Currency,
			&d.Message, &d.Amount, &d.PaymentStatus, &d.DeliveryStatus,
			&d.PaymentMethod, &d.ImpactNote, &d.TransactionDate,
		)
		if err != nil {
			return nil, emptyStats, err
		}
		if d.DonationKind == "general" {
			gn, gnAr := "General Support", "الدعم العام"
			d.CampaignName = &gn
			d.CampaignNameAr = &gnAr
		}
		items = append(items, d)
	}
	if err := rows.Err(); err != nil {
		return nil, emptyStats, err
	}

	// Stats — amount is stored as VARCHAR, so cast to NUMERIC for math.
	var stats Stats
	err = s.Pool.QueryRow(ctx, `
		SELECT
		  COUNT(*) AS total_count,
		  COALESCE(SUM(NULLIF(amount,'')::numeric), 0) AS total_amount,
		  SUM(CASE WHEN payment_status = 1 THEN 1 ELSE 0 END) AS success_count,
		  COALESCE(SUM(CASE WHEN payment_status = 1 THEN NULLIF(amount,'')::numeric ELSE 0 END), 0) AS success_amount,
		  SUM(CASE WHEN payment_status = 2 THEN 1 ELSE 0 END) AS pending_count,
		  COALESCE(SUM(CASE WHEN payment_status = 2 THEN NULLIF(amount,'')::numeric ELSE 0 END), 0) AS pending_amount,
		  SUM(CASE WHEN payment_status = 3 THEN 1 ELSE 0 END) AS failed_count,
		  COALESCE(SUM(CASE WHEN payment_status = 3 THEN NULLIF(amount,'')::numeric ELSE 0 END), 0) AS failed_amount
		FROM donations
		WHERE user_id = $1`,
		userID,
	).Scan(
		&stats.TotalCount, &stats.TotalAmount,
		&stats.SuccessCount, &stats.SuccessAmount,
		&stats.PendingCount, &stats.PendingAmount,
		&stats.FailedCount, &stats.FailedAmount,
	)
	if err != nil {
		return items, emptyStats, err
	}
	return items, stats, nil
}

// AdminListRow is the row shape for the admin /api/donations table view —
// donation columns plus joined donor info (phone, full_name) and campaign title.
type AdminListRow struct {
	ID              int64     `json:"id"`
	ReferenceNumber *string   `json:"reference_number"`
	UserID          int64     `json:"user_id"`
	DonorPhone      string    `json:"donor_phone"`
	DonorFullName   *string   `json:"donor_full_name"`
	CampaignID      *int64    `json:"campaign_id"`
	CampaignTitle   *string   `json:"campaign_title"`
	DonationKind    string    `json:"donation_kind"`
	DonationType    string    `json:"donation_type"`
	Amount          string    `json:"amount"`
	Currency        string    `json:"currency"`
	PaymentStatus   int       `json:"payment_status"`
	DeliveryStatus  string    `json:"delivery_status"`
	PaymentMethod   string    `json:"payment_method"`
	TransactionDate time.Time `json:"transaction_date"`
}

// AdminPage is the page response for AdminList.
type AdminPage struct {
	Items      []AdminListRow `json:"items"`
	Page       int            `json:"page"`
	PerPage    int            `json:"per_page"`
	TotalItems int            `json:"total_items"`
	TotalPages int            `json:"total_pages"`
	HasMore    bool           `json:"has_more"`
}

// AdminList returns a paginated list of all donations (admin view) with joined
// donor and campaign info.
// AdminList returns paginated donations. q searches reference_number, donor
// name (joined user_profiles), donor phone, and payment_method.
func (s *Store) AdminList(ctx context.Context, page, perPage int, q string) (*AdminPage, error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 200 {
		perPage = 20
	}
	offset := (page - 1) * perPage

	args := []any{}
	where := ""
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		where = ` WHERE (d.reference_number ILIKE $1 OR u.phone ILIKE $1 OR up.full_name ILIKE $1 OR d.payment_method ILIKE $1)`
	}

	var total int
	if err := s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM donations d
		   LEFT JOIN users u ON u.id = d.user_id
		   LEFT JOIN user_profiles up ON up.user_id = d.user_id`+where,
		args...,
	).Scan(&total); err != nil {
		return nil, err
	}

	limIdx := len(args) + 1
	offIdx := len(args) + 2
	args = append(args, perPage, offset)
	// Phase 18c — join campaigns (the table donations.campaign_id actually
	// references) instead of beneficiary_project_requests. See the comment
	// on ListByUser above for the full history.
	rows, err := s.Pool.Query(ctx, `
		SELECT d.id, d.reference_number, d.user_id, u.phone, up.full_name,
		       d.campaign_id, c.title,
		       d.donation_kind, d.donation_type, d.amount,
		       'IQD'::text AS currency,
		       d.payment_status, d.delivery_status, d.payment_method, d.transaction_date
		  FROM donations d
		  LEFT JOIN users u ON u.id = d.user_id
		  LEFT JOIN user_profiles up ON up.user_id = d.user_id
		  LEFT JOIN campaigns c ON c.id = d.campaign_id`+where+`
		 ORDER BY d.transaction_date DESC, d.id DESC
		 LIMIT $`+itoa(limIdx)+` OFFSET $`+itoa(offIdx),
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []AdminListRow{}
	for rows.Next() {
		var r AdminListRow
		if err := rows.Scan(&r.ID, &r.ReferenceNumber, &r.UserID, &r.DonorPhone, &r.DonorFullName,
			&r.CampaignID, &r.CampaignTitle,
			&r.DonationKind, &r.DonationType, &r.Amount, &r.Currency,
			&r.PaymentStatus, &r.DeliveryStatus, &r.PaymentMethod, &r.TransactionDate); err != nil {
			return nil, err
		}
		if r.DonationKind == "general" && (r.CampaignTitle == nil || *r.CampaignTitle == "") {
			gn := "General Support"
			r.CampaignTitle = &gn
		}
		items = append(items, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	totalPages := (total + perPage - 1) / perPage
	if totalPages < 1 {
		totalPages = 1
	}
	return &AdminPage{
		Items:      items,
		Page:       page,
		PerPage:    perPage,
		TotalItems: total,
		TotalPages: totalPages,
		HasMore:    page < totalPages,
	}, nil
}

func randHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
