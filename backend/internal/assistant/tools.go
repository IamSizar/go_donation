package assistant

import (
	"context"
	"encoding/json"

	"github.com/karam-flutter/humanitarian-backend/internal/beneficiary"
	"github.com/karam-flutter/humanitarian-backend/internal/donations"
	"github.com/karam-flutter/humanitarian-backend/internal/marriage"
	"github.com/karam-flutter/humanitarian-backend/internal/volunteers"
	"github.com/karam-flutter/humanitarian-backend/internal/wallet"
)

// Deps are the read-only data sources the assistant's tools query. Every
// tool call below is scoped to the CALLING user's own userID, which is
// injected server-side (see executeToolCall) — the model is never given a
// way to supply a user_id itself, so no amount of prompt injection can make
// it read someone else's wallet, donations, case, or profile.
type Deps struct {
	Wallet      *wallet.Store
	Donations   *donations.Store
	Marriage    *marriage.Store
	Beneficiary *beneficiary.Store
	Volunteers  *volunteers.Store
}

// toolDef mirrors the Anthropic Messages API tool schema.
type toolDef struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	InputSchema json.RawMessage `json:"input_schema"`
}

// emptySchema — every tool here takes no arguments; all of them answer
// "about the current user", so there's nothing for the model to supply.
var emptySchema = json.RawMessage(`{"type":"object","properties":{}}`)

const (
	toolWalletBalance = "get_wallet_balance"
	toolMyDonations   = "get_my_donations"
	toolMyMarriage    = "get_my_marriage_profile"
	toolMyBeneficiary = "get_my_beneficiary_status"
	toolMyVolunteer   = "get_my_volunteer_status"
)

// toolsFor returns the tools available to a role, mirroring the same
// role-based feature split the rest of the assistant already uses
// (allowedRoutes/capabilityText). Wallet and the marriage profile are common
// to every role since Note #43 opened Marriage submission to all accounts.
func toolsFor(roleID int) []toolDef {
	out := []toolDef{
		{
			Name:        toolWalletBalance,
			Description: "Get the current user's app wallet balance (IQD) and their most recent transactions. Use this whenever the user asks about their wallet, balance, or recent wallet activity — never guess a number.",
			InputSchema: emptySchema,
		},
		{
			Name:        toolMyMarriage,
			Description: "Get the current user's own marriage/engagement profile(s): status, subscription tier, and visibility setting. Use this when the user asks about their marriage profile or subscription status.",
			InputSchema: emptySchema,
		},
	}
	switch roleID {
	case 2: // Eligible / Beneficiary
		out = append(out, toolDef{
			Name:        toolMyBeneficiary,
			Description: "Get the current user's own beneficiary case(s) and submitted project/campaign request(s): verification status, priority, and funding progress. Use this when the user asks about their case or project status.",
			InputSchema: emptySchema,
		})
	case 3: // Volunteer
		out = append(out, toolDef{
			Name:        toolMyVolunteer,
			Description: "Get the current user's volunteer mission signups: status, hours served, and which missions they've joined. Use this when the user asks about their volunteer status or hours.",
			InputSchema: emptySchema,
		})
	default: // Grantor / Donor
		out = append(out, toolDef{
			Name:        toolMyDonations,
			Description: "Get the current user's own donation history and stats: totals, and recent donations with their status. Use this when the user asks about their donations or donation history.",
			InputSchema: emptySchema,
		})
	}
	return out
}

// executeToolCall runs one tool call, scoped to userID, and returns a
// compact JSON result string for the model. Errors come back as a JSON
// {"error": "..."} object (never a Go error) so the model can apologize and
// keep going rather than the whole turn failing.
func executeToolCall(ctx context.Context, deps Deps, userID int64, name string) string {
	switch name {
	case toolWalletBalance:
		return toolGetWalletBalance(ctx, deps, userID)
	case toolMyDonations:
		return toolGetMyDonations(ctx, deps, userID)
	case toolMyMarriage:
		return toolGetMyMarriage(ctx, deps, userID)
	case toolMyBeneficiary:
		return toolGetMyBeneficiary(ctx, deps, userID)
	case toolMyVolunteer:
		return toolGetMyVolunteer(ctx, deps, userID)
	default:
		return `{"error":"unknown tool"}`
	}
}

type walletTxSummary struct {
	AmountIQD int64  `json:"amount_iqd"`
	Type      string `json:"type"`
	Date      string `json:"date"`
}

func toolGetWalletBalance(ctx context.Context, deps Deps, userID int64) string {
	if deps.Wallet == nil {
		return `{"error":"wallet is not available"}`
	}
	balance, err := deps.Wallet.GetBalance(ctx, userID)
	if err != nil {
		return `{"error":"could not load wallet balance"}`
	}
	txs, _ := deps.Wallet.ListTransactions(ctx, userID, 1, 5)
	out := struct {
		BalanceIQD int64             `json:"balance_iqd"`
		Recent     []walletTxSummary `json:"recent_transactions"`
	}{BalanceIQD: balance, Recent: []walletTxSummary{}}
	for _, t := range txs {
		out.Recent = append(out.Recent, walletTxSummary{
			AmountIQD: t.AmountIQD, Type: t.Type, Date: t.CreatedAt.Format("2006-01-02"),
		})
	}
	b, _ := json.Marshal(out)
	return string(b)
}

func paymentStatusLabel(status int) string {
	switch status {
	case 1:
		return "success"
	case 2:
		return "pending"
	case 3:
		return "failed"
	default:
		return "unknown"
	}
}

func toolGetMyDonations(ctx context.Context, deps Deps, userID int64) string {
	if deps.Donations == nil {
		return `{"error":"donations are not available"}`
	}
	rows, stats, err := deps.Donations.ListByUser(ctx, userID)
	if err != nil {
		return `{"error":"could not load donation history"}`
	}
	type recentDonation struct {
		Campaign       string `json:"campaign"`
		Amount         string `json:"amount"`
		Currency       string `json:"currency"`
		PaymentStatus  string `json:"payment_status"`
		DeliveryStatus string `json:"delivery_status"`
		Date           string `json:"date"`
	}
	out := struct {
		Stats  donations.Stats  `json:"stats"`
		Recent []recentDonation `json:"recent"`
	}{Stats: stats, Recent: []recentDonation{}}
	limit := len(rows)
	if limit > 5 {
		limit = 5
	}
	for _, r := range rows[:limit] {
		name := "General"
		if r.CampaignName != nil && *r.CampaignName != "" {
			name = *r.CampaignName
		}
		out.Recent = append(out.Recent, recentDonation{
			Campaign: name, Amount: r.Amount, Currency: r.Currency,
			PaymentStatus:  paymentStatusLabel(r.PaymentStatus),
			DeliveryStatus: r.DeliveryStatus,
			Date:           r.TransactionDate.Format("2006-01-02"),
		})
	}
	b, _ := json.Marshal(out)
	return string(b)
}

func toolGetMyMarriage(ctx context.Context, deps Deps, userID int64) string {
	if deps.Marriage == nil {
		return `{"error":"marriage profiles are not available"}`
	}
	profiles, err := deps.Marriage.List(ctx, marriage.SearchFilters{Status: "all", OwnedByUser: userID, Limit: 5})
	if err != nil {
		return `{"error":"could not load marriage profile"}`
	}
	type profileSummary struct {
		ProfileCode      string `json:"profile_code"`
		Status           string `json:"status"`
		SubscriptionTier string `json:"subscription_tier"`
		VisibilityLevel  string `json:"visibility"`
	}
	out := struct {
		Profiles []profileSummary `json:"profiles"`
	}{Profiles: []profileSummary{}}
	for _, p := range profiles {
		out.Profiles = append(out.Profiles, profileSummary{
			ProfileCode: p.ProfileCode, Status: p.Status,
			SubscriptionTier: p.SubscriptionStatus, VisibilityLevel: p.VisibilityLevel,
		})
	}
	b, _ := json.Marshal(out)
	return string(b)
}

func toolGetMyBeneficiary(ctx context.Context, deps Deps, userID int64) string {
	if deps.Beneficiary == nil {
		return `{"error":"beneficiary data is not available"}`
	}
	cases, err := deps.Beneficiary.ListCasesForUser(ctx, userID, "all", 5)
	if err != nil {
		return `{"error":"could not load case status"}`
	}
	requests, err := deps.Beneficiary.ListRequestsForUser(ctx, userID, "all", 5)
	if err != nil {
		return `{"error":"could not load project requests"}`
	}
	type caseSummary struct {
		CaseCode           string `json:"case_code"`
		VerificationStatus string `json:"verification_status"`
		PriorityLevel      string `json:"priority_level"`
	}
	type requestSummary struct {
		Title        string `json:"title"`
		Status       string `json:"status"`
		AmountNeeded string `json:"amount_needed"`
		RaisedAmount int    `json:"raised_amount"`
		Currency     string `json:"currency"`
	}
	out := struct {
		Cases           []caseSummary    `json:"cases"`
		ProjectRequests []requestSummary `json:"project_requests"`
	}{Cases: []caseSummary{}, ProjectRequests: []requestSummary{}}
	for _, cs := range cases {
		verification := "not_reviewed"
		if cs.VerificationStatus != nil && *cs.VerificationStatus != "" {
			verification = *cs.VerificationStatus
		}
		out.Cases = append(out.Cases, caseSummary{
			CaseCode: cs.CaseCode, VerificationStatus: verification, PriorityLevel: cs.PriorityLevel,
		})
	}
	for _, r := range requests {
		out.ProjectRequests = append(out.ProjectRequests, requestSummary{
			Title: r.ProjectTitle, Status: r.Status, AmountNeeded: r.AmountNeeded,
			RaisedAmount: r.RaisedAmount, Currency: r.Currency,
		})
	}
	b, _ := json.Marshal(out)
	return string(b)
}

func toolGetMyVolunteer(ctx context.Context, deps Deps, userID int64) string {
	if deps.Volunteers == nil {
		return `{"error":"volunteer data is not available"}`
	}
	joined, err := deps.Volunteers.JoinedMissionsForUser(ctx, userID)
	if err != nil {
		return `{"error":"could not load volunteer status"}`
	}
	type missionSummary struct {
		Title        string `json:"title"`
		SignupStatus string `json:"signup_status"`
		HoursServed  string `json:"hours_served"`
	}
	out := struct {
		JoinedMissions []missionSummary `json:"joined_missions"`
	}{JoinedMissions: []missionSummary{}}
	limit := len(joined)
	if limit > 5 {
		limit = 5
	}
	for _, j := range joined[:limit] {
		out.JoinedMissions = append(out.JoinedMissions, missionSummary{
			Title: j.Mission.Title, SignupStatus: j.SignupStatus, HoursServed: j.HoursServed,
		})
	}
	b, _ := json.Marshal(out)
	return string(b)
}
