// chat_group_admin_connect_party.go — the OTHER PARTY of a connect request as
// the admin inbox shows it: who the case or campaign behind the request
// belongs to.
//
// # WHY IT IS SHOWN
//
// Before this, the inbox resolved a request's context to a human-readable
// LABEL only ("Case CSE-000007 — …") and nothing else, so the approve dialog
// had nobody to name and staff had to find the right person by hand — or, as
// the client did, approve without one and open a group with a single member in
// it. The server now adds that person itself on approve
// (chatgroups.ApproveConnectRequest); these fields let the dashboard SHOW who
// that will be, and let staff swap them for somebody else.
//
// # WHAT IS GATED, AND WHAT IS NOT
//
// The NAME follows requester_name exactly: present only for a caller who may
// view sensitive data, resolved per user by canViewContact (decision D6).
//
// The USER ID is NOT gated, deliberately. The inbox already ships
// requester_user_id and context_id to every caller who may read it at all;
// D6 is about putting a real NAME next to a masked identity, which is what
// sensitive_data means everywhere else in this codebase (see
// admin_contact_view.go). The dialog needs the id to pre-fill a member, and
// gating it would leave staff without sensitive_data doing by hand exactly the
// error-prone search this change removes — while an opaque integer tells them
// nothing about who the person is.
package handlers

import (
	"context"
)

// caseOtherPartySQL resolves a beneficiary case's owner and their profile
// name. beneficiary_cases.user_id is the owning member (migration
// 001_full_v2.sql:168); it is nullable, so an ownerless case comes back as
// NULL and this endpoint simply omits the fields.
//
// The name comes through a LATERAL subquery ordered by id, not a plain join,
// for the same reason adminConnectRequestSelect uses one: user_profiles.user_id
// carries no UNIQUE constraint, so a person with two profile rows would
// otherwise multiply the row. The oldest profile row names them.
const caseOtherPartySQL = `
	SELECT b.user_id, p.full_name
	  FROM beneficiary_cases b
	  LEFT JOIN LATERAL (SELECT up.full_name
	                       FROM user_profiles up
	                      WHERE up.user_id = b.user_id
	                      ORDER BY up.id
	                      LIMIT 1) p ON true
	 WHERE b.id = $1`

// donationOtherPartySQL resolves the owner of the campaign a donation was made
// to, and their profile name. campaigns.owner_user_id is the beneficiary who
// owns a published campaign (migrations/007_campaigns_owner.sql:18). A donation
// to the GENERAL FUND has no campaign_id, so the join matches nothing and the
// request has no other party — which is the truth, not an error.
const donationOtherPartySQL = `
	SELECT c.owner_user_id, p.full_name
	  FROM donations d
	  JOIN campaigns c ON c.id = d.campaign_id
	  LEFT JOIN LATERAL (SELECT up.full_name
	                       FROM user_profiles up
	                      WHERE up.user_id = c.owner_user_id
	                      ORDER BY up.id
	                      LIMIT 1) p ON true
	 WHERE d.id = $1`

// connectParty is the other party of one connect request, as far as it could
// be resolved. Both fields are nil when there is nobody — a general-fund
// donation, a campaign with no owner, an ownerless case, a context row that
// has been deleted, or a lookup that failed.
type connectParty struct {
	userID *int64
	name   *string
}

// resolveConnectParty finds the user the request's context belongs to.
//
// BEST-EFFORT, exactly like resolveConnectContext beside it: a failed lookup
// yields no other party rather than breaking the whole inbox listing. The
// fields are then simply absent and the dashboard falls back to staff picking
// the member themselves. Nothing here can refuse a request or fail a page.
//
// Note this is the DISPLAY copy of the question. The authoritative one, which
// decides membership and must not swallow errors, is
// chatgroups.connectContextOwner, inside the approval's transaction.
func (h *ChatGroupHandler) resolveConnectParty(ctx context.Context, contextType string, contextID int64) connectParty {
	var query string
	switch contextType {
	case "case":
		query = caseOtherPartySQL
	case "donation":
		query = donationOtherPartySQL
	default:
		return connectParty{}
	}
	var party connectParty
	if err := h.Pool.QueryRow(ctx, query, contextID).Scan(&party.userID, &party.name); err != nil {
		return connectParty{}
	}
	if party.userID == nil {
		return connectParty{} // no owner means no name to show either
	}
	return party
}
