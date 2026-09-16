// chatgroups_connect_party.go — who a connect request's context belongs to,
// and how that person becomes a member of the group the approval opens.
//
// # WHY THIS FILE EXISTS
//
// A connect request has two sides: the member who filed it, and whoever the
// case or campaign it names belongs to. Until this file only the first was
// ever resolved, so approving a request from a beneficiary case opened a group
// containing the donor alone — one member, nobody to talk to. That is the bug
// the client found on the live deployment.
//
// The other party is now resolved and added by the SERVER, inside the
// approval's own transaction (ApproveConnectRequest), so the group is never
// created half-formed and staff never have to search for the right person by
// hand. Membership is not a dashboard decision any more; the dashboard only
// shows what will happen and may override it.
//
// Split out of chatgroups_connect.go so that file stays well under the
// 500-line cap.

package chatgroups

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// caseOwnerSQL reads the member a beneficiary case belongs to.
// beneficiary_cases.user_id is that column: it is what the case's own reads
// filter by (internal/dashboard/dashboard.go:250) and what the mobile app
// files a case under. It is nullable — an ownerless case, which the public
// case list already has a test for — so it is scanned into a pointer.
const caseOwnerSQL = `SELECT user_id FROM beneficiary_cases WHERE id = $1`

// donationOwnerSQL reads the owner of the campaign a donation was made to.
// campaigns.owner_user_id is the beneficiary who owns a published campaign
// (migrations/007_campaigns_owner.sql:18); it is NULL for the admin-curated
// campaigns, and a donation to the GENERAL FUND has no campaign_id at all.
// Both cases come back as no owner, which is the truth: such a donation has
// no other party, and nothing is invented for it.
const donationOwnerSQL = `
	SELECT c.owner_user_id
	  FROM donations d
	  JOIN campaigns c ON c.id = d.campaign_id
	 WHERE d.id = $1`

// connectContextOwner returns the user the request's context belongs to, and
// whether there is one at all.
//
// No owner is a normal answer, not a failure: a donation to the general fund,
// a campaign with no beneficiary owner, an ownerless case, or a context row
// that has since been deleted. A context_type this package does not know
// answers the same way, so a future type cannot silently add a wrong member.
//
// A real database error IS returned, because this runs inside the approval's
// transaction: swallowing it would open exactly the half-formed group this
// whole change exists to prevent.
func connectContextOwner(ctx context.Context, q memberExecer, contextType string, contextID int64) (int64, bool, error) {
	var query string
	switch contextType {
	case "case":
		query = caseOwnerSQL
	case "donation":
		query = donationOwnerSQL
	default:
		return 0, false, nil
	}
	var owner *int64
	if err := q.QueryRow(ctx, query, contextID).Scan(&owner); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, false, nil // the case or donation is gone; no other party
		}
		return 0, false, fmt.Errorf("chatgroups: resolving the owner of %s %d: %w", contextType, contextID, err)
	}
	if owner == nil {
		return 0, false, nil
	}
	return *owner, true, nil
}

// accountRoleWords maps users.role_id onto the role word chat groups use.
// The ids are registration's own (see roleIDDonor and roleIDBeneficiary in
// chatgroups_members.go), and the words are the keys autoLabelName knows, so
// an auto-added member gets the right numbered label ("Donor 1",
// "Beneficiary 1") without anyone typing one.
var accountRoleWords = map[int]string{1: "donor", 2: "beneficiary", 3: "volunteer"}

// accountRoleWord is the role_in_group to file userID under when no caller
// supplied one. An account with no users row, no role_id, or a role_id outside
// the three registration assigns falls back to "member", which autoLabel
// renders as "Member 1" — a neutral label, never a wrong one.
func accountRoleWord(ctx context.Context, q memberExecer, userID int64) (string, error) {
	var roleID *int
	if err := q.QueryRow(ctx, `SELECT role_id FROM users WHERE id = $1`, userID).Scan(&roleID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "member", nil
		}
		return "", fmt.Errorf("chatgroups: reading the account role of user %d: %w", userID, err)
	}
	if roleID == nil {
		return "member", nil
	}
	if word, ok := accountRoleWords[*roleID]; ok {
		return word, nil
	}
	return "member", nil
}

// hasMember reports whether members already names userID.
func hasMember(members []MemberInput, userID int64) bool {
	for _, m := range members {
		if m.UserID == userID {
			return true
		}
	}
	return false
}

// connectGroupMembers is the member list ApproveConnectRequest actually
// writes: what the caller sent, plus the two people the request is about when
// they are missing from it.
//
//   - The REQUESTER is added when the caller sent no members at all, so staff
//     can approve a request without typing anything. A caller who DID send
//     members must still name the requester — the existing rule, unchanged:
//     a list that deliberately leaves them out is a mistake worth refusing,
//     not a list to silently correct.
//   - The OTHER PARTY — the case's owner, or the owner of the campaign the
//     donation went to — is added whenever the context resolves to one and
//     they are not already listed. Sending them yourself is fine and keeps
//     your own label and role; they are never added twice, so the
//     (group_id, user_id) unique rule is never hit by this.
//
// A request whose other party cannot be resolved (a general-fund donation, an
// ownerless case) is approved exactly as it was before this existed.
//
// Auto-added members carry no label, so insertMembers gives them the next
// auto-generated one for their role — the same rule a blank label from the
// dashboard already gets.
func connectGroupMembers(ctx context.Context, q memberExecer, requestID, requesterID int64, contextType string, contextID int64, members []MemberInput) ([]MemberInput, error) {
	out := members
	if len(out) == 0 {
		role, err := accountRoleWord(ctx, q, requesterID)
		if err != nil {
			return nil, err
		}
		out = []MemberInput{{UserID: requesterID, RoleInGroup: role}}
	} else if !hasMember(out, requesterID) {
		return nil, fmt.Errorf("chatgroups: approving connect request %d: requester %d not in members: %w",
			requestID, requesterID, ErrInvalidInput)
	}

	owner, ok, err := connectContextOwner(ctx, q, contextType, contextID)
	if err != nil {
		return nil, err
	}
	if !ok || hasMember(out, owner) {
		return out, nil
	}
	role, err := accountRoleWord(ctx, q, owner)
	if err != nil {
		return nil, err
	}
	return append(out, MemberInput{UserID: owner, RoleInGroup: role}), nil
}
