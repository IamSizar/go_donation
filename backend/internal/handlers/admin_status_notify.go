// admin_status_notify.go — Phase 18 — the "decision notification" wiring
// that was silently missing in the Go port.
//
// Each handler in admin_status.go now fires the relevant notify.Notifier
// helper after a successful UPDATE. We keep the lookup + send code in a
// dedicated file so admin_status.go stays focused on validation.
//
// Conventions:
//   - Every helper takes (ctx, id, newStatus) — the same shape as the
//     callback updateStringStatus now invokes.
//   - Helpers swallow lookup / send errors (only log them) so a slow
//     network or DB hiccup never fails the admin's UPDATE response.
//   - Status transitions that don't warrant a notification (e.g. "draft"
//     or admin moving between two intermediate states) return early.
//
// Owner-column reference (verified against the seeded DB on 2026-05-17):
//
//	beneficiary_cases             → user_id
//	beneficiary_project_requests  → user_id
//	marketplace_orders            → buyer_user_id
//	marriage_profiles             → user_id
//	volunteer_applications        → user_id
//	sponsorships                  → donor_user_id
//	in_kind_donations             → donor_user_id
//	support_tickets               → user_id
//	volunteer_mission_signups     → user_id
//	donations                     → user_id  (and campaign_id → campaigns.user_id)

package handlers

import (
	"context"
	"errors"
	"log"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// notifyOptional is the "skip if not wired" guard used everywhere — when
// AdminStatusHandler was constructed without a notifier (e.g. in unit
// tests), every notify-* helper turns into a no-op.
func (h *AdminStatusHandler) notifyOptional() bool {
	return h.Notifier == nil
}

// --- Beneficiary cases ----------------------------------------------------

func (h *AdminStatusHandler) notifyBeneficiaryCaseDecision(ctx context.Context, caseID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	var userID *int64
	var title string
	err := h.Pool.QueryRow(ctx,
		`SELECT user_id, public_title FROM beneficiary_cases WHERE id = $1`,
		caseID,
	).Scan(&userID, &title)
	if err != nil {
		log.Printf("[notify] case %d lookup: %v", caseID, err)
		return
	}
	if userID == nil || *userID <= 0 {
		return
	}
	var msg notify.LocalizedMessage
	switch newStatus {
	case "approved":
		msg = notify.BeneficiaryCaseApprovedMsg(title, caseID)
	case "rejected":
		msg = notify.BeneficiaryCaseRejectedMsg(title, caseID)
	default:
		return
	}
	if _, err := h.Notifier.Send(ctx, *userID, msg); err != nil {
		log.Printf("[notify] case %d send: %v", caseID, err)
	}
}

// --- Project requests -----------------------------------------------------

func (h *AdminStatusHandler) notifyProjectRequestDecision(ctx context.Context, requestID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	var userID int64
	var title string
	err := h.Pool.QueryRow(ctx,
		`SELECT user_id, project_title FROM beneficiary_project_requests WHERE id = $1`,
		requestID,
	).Scan(&userID, &title)
	if err != nil {
		log.Printf("[notify] project_request %d lookup: %v", requestID, err)
		return
	}
	if userID <= 0 {
		return
	}
	var msg notify.LocalizedMessage
	switch newStatus {
	case "approved":
		msg = notify.ProjectRequestApprovedMsg(title, requestID)
	case "rejected":
		msg = notify.ProjectRequestRejectedMsg(title, requestID)
	case "under_review", "pending":
		// These get a generic "status updated" so the beneficiary knows
		// admin opened the request without committing to a decision yet.
		msg = notify.ProjectRequestStatusChangedMsg(title, newStatus, requestID)
	default:
		return
	}
	if _, err := h.Notifier.Send(ctx, userID, msg); err != nil {
		log.Printf("[notify] project_request %d send: %v", requestID, err)
	}
}

// --- Marketplace orders ---------------------------------------------------

func (h *AdminStatusHandler) notifyMarketplaceOrderDecision(ctx context.Context, orderID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	var buyerID *int64
	var productName string
	var qty int
	var total string
	var currency string
	err := h.Pool.QueryRow(ctx, `
		SELECT o.buyer_user_id, COALESCE(p.name, ''), o.quantity, o.total_amount, o.currency
		  FROM marketplace_orders o
		  LEFT JOIN marketplace_products p ON p.id = o.product_id
		 WHERE o.id = $1`,
		orderID,
	).Scan(&buyerID, &productName, &qty, &total, &currency)
	if err != nil {
		log.Printf("[notify] order %d lookup: %v", orderID, err)
		return
	}
	if buyerID == nil || *buyerID <= 0 {
		return
	}
	var msg notify.LocalizedMessage
	switch newStatus {
	case "approved", "processing":
		msg = notify.MarketplaceOrderApprovedMsg(productName, qty, total, currency, orderID)
	case "completed":
		msg = notify.MarketplaceOrderCompletedMsg(productName, qty, orderID)
	case "cancelled":
		msg = notify.MarketplaceOrderCancelledMsg(productName, qty, orderID)
	default:
		return
	}
	if _, err := h.Notifier.Send(ctx, *buyerID, msg); err != nil {
		log.Printf("[notify] order %d send: %v", orderID, err)
	}
}

// --- Marriage profiles ----------------------------------------------------

func (h *AdminStatusHandler) notifyMarriageDecision(ctx context.Context, profileID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	var userID *int64
	var code string
	err := h.Pool.QueryRow(ctx,
		`SELECT user_id, profile_code FROM marriage_profiles WHERE id = $1`,
		profileID,
	).Scan(&userID, &code)
	if err != nil {
		log.Printf("[notify] marriage %d lookup: %v", profileID, err)
		return
	}
	if userID == nil || *userID <= 0 {
		return
	}
	var msg notify.LocalizedMessage
	switch newStatus {
	case "active", "matched":
		msg = notify.MarriageApprovedMsg(code, profileID)
	case "rejected", "closed":
		msg = notify.MarriageRejectedMsg(code, profileID)
	case "paused":
		msg = notify.MarriageStatusChangedMsg(code, newStatus, profileID)
	default:
		return
	}
	if _, err := h.Notifier.Send(ctx, *userID, msg); err != nil {
		log.Printf("[notify] marriage %d send: %v", profileID, err)
	}
}

// --- Volunteer application ------------------------------------------------

func (h *AdminStatusHandler) notifyVolunteerAppDecision(ctx context.Context, appID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	var userID *int64
	var fullName string
	err := h.Pool.QueryRow(ctx,
		`SELECT user_id, full_name FROM volunteer_applications WHERE id = $1`,
		appID,
	).Scan(&userID, &fullName)
	if err != nil {
		log.Printf("[notify] volunteer_app %d lookup: %v", appID, err)
		return
	}
	if userID == nil || *userID <= 0 {
		return
	}
	// Only the 3 explicit decision states trigger a notification — submitted
	// is the default landing state and doesn't need one.
	if newStatus != "approved" && newStatus != "rejected" && newStatus != "inactive" {
		return
	}
	msg := notify.VolunteerApplicationDecisionMsg(fullName, newStatus, appID)
	if _, err := h.Notifier.Send(ctx, *userID, msg); err != nil {
		log.Printf("[notify] volunteer_app %d send: %v", appID, err)
	}
}

// --- Sponsorships ---------------------------------------------------------

func (h *AdminStatusHandler) notifySponsorshipDecision(ctx context.Context, sponsorshipID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	var donorID int64
	var amount string
	var currency *string
	var projectTitle string
	// Sponsorships reference either a beneficiary_case or a project_request
	// for their "what is this sponsoring" label. Try project_request first
	// (the more common case) then fall back to case.
	err := h.Pool.QueryRow(ctx, `
		SELECT s.donor_user_id,
		       s.amount,
		       s.currency,
		       COALESCE(pr.project_title, bc.public_title, '')
		  FROM sponsorships s
		  LEFT JOIN beneficiary_project_requests pr ON pr.id = s.project_request_id
		  LEFT JOIN beneficiary_cases             bc ON bc.id = s.beneficiary_case_id
		 WHERE s.id = $1`,
		sponsorshipID,
	).Scan(&donorID, &amount, &currency, &projectTitle)
	if err != nil {
		log.Printf("[notify] sponsorship %d lookup: %v", sponsorshipID, err)
		return
	}
	if donorID <= 0 {
		return
	}
	cur := ""
	if currency != nil {
		cur = *currency
	}
	var msg notify.LocalizedMessage
	switch newStatus {
	case "active":
		msg = notify.SponsorshipAcceptedMsg(amount, cur, projectTitle, sponsorshipID)
	case "cancelled", "stopped":
		// Same copy as the donor-initiated cancel — admin-initiated lands
		// on the same notification so the donor sees a clean record.
		msg = notify.SponsorshipCancelledByDonorMsg(projectTitle, sponsorshipID)
	case "paused", "delayed", "completed":
		msg = notify.SponsorshipStatusChangedMsg(projectTitle, newStatus, sponsorshipID)
	default:
		return
	}
	if _, err := h.Notifier.Send(ctx, donorID, msg); err != nil {
		log.Printf("[notify] sponsorship %d send: %v", sponsorshipID, err)
	}
}

// --- In-kind donations ----------------------------------------------------

func (h *AdminStatusHandler) notifyInKindDecision(ctx context.Context, inKindID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	var donorID *int64
	var itemName string
	var qty *string
	err := h.Pool.QueryRow(ctx,
		`SELECT donor_user_id, item_name, quantity FROM in_kind_donations WHERE id = $1`,
		inKindID,
	).Scan(&donorID, &itemName, &qty)
	if err != nil {
		log.Printf("[notify] in_kind %d lookup: %v", inKindID, err)
		return
	}
	if donorID == nil || *donorID <= 0 {
		return
	}
	// Phase 23 — proper per-state templates. The earlier "borrow marketplace
	// copy with hardcoded 1 ×" hack is gone; each state has its own
	// 4-language template with the actual quantity field.
	qtyStr := ""
	if qty != nil {
		qtyStr = *qty
	}
	var msg notify.LocalizedMessage
	switch newStatus {
	case "scheduled":
		msg = notify.InKindScheduledMsg(itemName, qtyStr, inKindID)
	case "received":
		msg = notify.InKindReceivedMsg(itemName, qtyStr, inKindID)
	case "delivered":
		msg = notify.InKindDeliveredMsg(itemName, qtyStr, inKindID)
	case "cancelled":
		msg = notify.InKindCancelledMsg(itemName, qtyStr, inKindID)
	default:
		return
	}
	if _, err := h.Notifier.Send(ctx, *donorID, msg); err != nil {
		log.Printf("[notify] in_kind %d send: %v", inKindID, err)
	}
}

// --- Support tickets ------------------------------------------------------

func (h *AdminStatusHandler) notifySupportTicketDecision(ctx context.Context, ticketID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	var userID *int64
	var subject string
	err := h.Pool.QueryRow(ctx,
		`SELECT user_id, subject FROM support_tickets WHERE id = $1`,
		ticketID,
	).Scan(&userID, &subject)
	if err != nil {
		log.Printf("[notify] support %d lookup: %v", ticketID, err)
		return
	}
	if userID == nil || *userID <= 0 {
		return
	}
	if newStatus != "in_progress" && newStatus != "resolved" && newStatus != "closed" {
		return
	}
	msg := notify.SupportTicketStatusMsg(subject, newStatus, ticketID)
	if _, err := h.Notifier.Send(ctx, *userID, msg); err != nil {
		log.Printf("[notify] support %d send: %v", ticketID, err)
	}
}

// --- Volunteer missions (status change) ----------------------------------

// notifyMissionStatusBroadcast fires the role=3 broadcast when an admin
// transitions a mission INTO the 'open' state from any other state (draft,
// closed, etc.). Re-opening a previously-open mission won't re-broadcast
// because the dedupe key (user + title + body + type) blocks duplicate rows
// — see notify.go:Send.
//
// Other transitions (open → closed / completed / cancelled) don't notify
// anyone here. Individual signup notifications are handled by the
// mission-signup status path when admin cancels/completes per-volunteer.
//
// Phase 22.
func (h *AdminStatusHandler) notifyMissionStatusBroadcast(ctx context.Context, missionID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	if newStatus != "open" {
		return
	}
	var title, city string
	var missionDate *string
	if err := h.Pool.QueryRow(ctx, `
		SELECT title, COALESCE(city, ''), to_char(mission_date, 'YYYY-MM-DD')
		  FROM volunteer_missions WHERE id = $1`,
		missionID,
	).Scan(&title, &city, &missionDate); err != nil {
		log.Printf("[notify] mission %d lookup: %v", missionID, err)
		return
	}
	dateText := ""
	if missionDate != nil {
		dateText = *missionDate
	}
	// Broadcast happens in background so the admin's status response isn't
	// blocked by the fan-out.
	go func() {
		bg, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		sent, err := h.Notifier.Broadcast(bg, 3 /* volunteers */,
			notify.NewVolunteerMissionMsg(title, city, dateText, missionID))
		if err != nil {
			log.Printf("[notify] mission %d broadcast: %v", missionID, err)
			return
		}
		log.Printf("[notify] mission %d opened — broadcast to %d volunteers", missionID, sent)
	}()
}

// --- Volunteer mission signups -------------------------------------------

// notifyMissionSignupDecision fires when an admin transitions a signup's
// status to one we have copy for. Looks up the volunteer + the mission
// title in one query so the body reads "Your request to join "Clean City"
// was approved" rather than "your request was approved".
//
// Phase 21.
func (h *AdminStatusHandler) notifyMissionSignupDecision(ctx context.Context, signupID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	var volunteerID int64
	var missionTitle string
	err := h.Pool.QueryRow(ctx, `
		SELECT s.user_id, COALESCE(m.title, '')
		  FROM volunteer_mission_signups s
		  LEFT JOIN volunteer_missions m ON m.id = s.mission_id
		 WHERE s.id = $1`,
		signupID,
	).Scan(&volunteerID, &missionTitle)
	if err != nil {
		log.Printf("[notify] mission_signup %d lookup: %v", signupID, err)
		return
	}
	if volunteerID <= 0 {
		return
	}

	// MissionSignupDecisionMsg's switch covers: approved, rejected, cancelled,
	// joined, completed, no_show, completion_requested. Anything else falls
	// through to the generic "status updated" branch; we just skip the
	// 'pending' state (it's the implicit starting state — no need to notify).
	if newStatus == "pending" {
		return
	}
	msg := notify.MissionSignupDecisionMsg(missionTitle, newStatus, signupID)
	if _, err := h.Notifier.Send(ctx, volunteerID, msg); err != nil {
		log.Printf("[notify] mission_signup %d send: %v", signupID, err)
	}
}

// --- Donations (admin decision) ------------------------------------------

// notifyDonationDecision fires when an admin updates a donation's
// delivery_status. Used for "approved" (delivered/received) and "rejected"
// (cancelled) transitions.
//
// The approval body includes the campaign's NEW raised total + goal so the
// donor can see the impact of their contribution at a glance. The raised
// total was already bumped at INSERT time (Phase 15), so reading it now
// gives the post-donation value without any extra writes.
func (h *AdminStatusHandler) notifyDonationDecision(ctx context.Context, donationID int64, newStatus string) {
	if h.notifyOptional() {
		return
	}
	var donorID int64
	var amount string
	var campaignName string
	// Donations.amount + campaigns.raised_amount/goal_amount are all varchar;
	// COALESCE with empty-string fallback so the formatter degrades cleanly.
	// Donations doesn't store a per-row currency today, so IQD is hard-coded
	// (matches what the rest of the stack assumes).
	var raised, goal string
	err := h.Pool.QueryRow(ctx, `
		SELECT d.user_id, d.amount,
		       COALESCE(c.title,         'general donation'),
		       COALESCE(c.raised_amount, '0'),
		       COALESCE(c.goal_amount,   '0')
		  FROM donations d
		  LEFT JOIN campaigns c ON c.id = d.campaign_id
		 WHERE d.id = $1`,
		donationID,
	).Scan(&donorID, &amount, &campaignName, &raised, &goal)
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			log.Printf("[notify] donation %d lookup: %v", donationID, err)
		}
		return
	}
	if donorID <= 0 {
		return
	}
	const currency = "IQD"
	var msg notify.LocalizedMessage
	switch newStatus {
	case "received", "delivered":
		// Pass raised + goal so the body reads e.g.
		//   "…campaign has now raised 250,000 of 5,000,000 IQD (5% of goal)…"
		msg = notify.DonationApprovedMsg(amount, currency, campaignName, raised, goal, donationID)
	case "cancelled":
		msg = notify.DonationRejectedMsg(amount, currency, campaignName, donationID)
	default:
		return
	}
	if _, err := h.Notifier.Send(ctx, donorID, msg); err != nil {
		log.Printf("[notify] donation %d send: %v", donationID, err)
	}
}

// notifyDonationPaymentDecision — Phase 27.2 — fires when an admin sets
// payment_status (1=success, 2=pending, 3=failed). Previously the donor
// got nothing when admin clicked "accept" because the existing
// notifyDonationDecision only listened to delivery_status. This handler
// fixes the "I accepted a donation but the donor never got a push" gap.
//
// Skips payment_status=2 (pending) — that's just a back-to-default
// click, not a meaningful event for the donor.
func (h *AdminStatusHandler) notifyDonationPaymentDecision(ctx context.Context, donationID int64, paymentStatus int) {
	if h.notifyOptional() {
		return
	}
	// Pending isn't a notification-worthy state. The donor already saw
	// "Donation submitted" when they posted it.
	if paymentStatus != 1 && paymentStatus != 3 {
		return
	}
	var donorID int64
	var amount string
	var campaignName string
	err := h.Pool.QueryRow(ctx, `
		SELECT d.user_id, d.amount,
		       COALESCE(c.title, 'general donation')
		  FROM donations d
		  LEFT JOIN campaigns c ON c.id = d.campaign_id
		 WHERE d.id = $1`,
		donationID,
	).Scan(&donorID, &amount, &campaignName)
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			log.Printf("[notify] donation %d lookup (payment): %v", donationID, err)
		}
		return
	}
	if donorID <= 0 {
		return
	}
	const currency = "IQD"
	var msg notify.LocalizedMessage
	switch paymentStatus {
	case 1:
		msg = notify.DonationPaymentConfirmedMsg(amount, currency, campaignName, donationID)
	case 3:
		msg = notify.DonationPaymentFailedMsg(amount, currency, campaignName, donationID)
	default:
		return
	}
	if _, err := h.Notifier.Send(ctx, donorID, msg); err != nil {
		log.Printf("[notify] donation %d payment send: %v", donationID, err)
	}
}
