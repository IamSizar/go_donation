// field_rule_enforcement.go — the SERVER half of owner item #15, "the
// dashboard form must match the app".
//
// WHY A SERVER HALF EXISTS AT ALL
// The dashboard can render an asterisk next to a required box and refuse to
// submit; that is UX, not enforcement. Anything that speaks HTTP — a stale tab
// still holding yesterday's rules, a curl, a future screen nobody has written
// yet — can post the same body without it. `registration_field_rules` is the
// place staff express "a Volunteer must give us a national ID", and a rule the
// server does not check is a preference, not a rule. So the same three states
// the app already honours are checked here, once, for every admin write to a
// user's profile.
//
// WHAT IS CHECKED, AND WHAT DELIBERATELY IS NOT
//
//	required → a column PRESENT in the body and blank is refused.
//	hidden   → a column PRESENT in the body with a value is refused.
//	optional → nothing.
//
// "Present in the body" is load-bearing in both directions:
//
//   - A required column the request never mentions is NOT refused. The admin
//     endpoints are partial updates (`PATCH .../:id` writes only the keys it
//     was sent), so demanding every required column on every request would
//     make it impossible to correct one phone number on an account registered
//     before the rule existed. Existing data is never held hostage — the same
//     decision the owner made for app users, who are PROMPTED and never
//     blocked (see humanitarian/lib/modules/profile/required_fields_prompt).
//
//   - A hidden column is refused only when it carries a VALUE. The dashboard
//     form drops hidden boxes entirely, but a blank string is indistinguishable
//     from "this box was not on my form", and turning that into a 400 would
//     punish an honest client for a field it never showed.
//
// The message names the field and says what to do, because "invalid request"
// on a 90-box form is the same as no message at all.
package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// fieldRuleViolation is one refused column, ready to be rendered as an error
// envelope. `Column` is echoed so the dashboard can focus the offending box
// rather than making the operator hunt for it.
type fieldRuleViolation struct {
	Code    string
	Column  string
	Message string
}

// checkFieldRules applies the rules of one namespace to one request body.
// Returns nil when the body is acceptable.
//
// prefix "" means "this account has no registration form" (a staff account, or
// role 0) and is not governed — see fieldRulePrefixForRole.
func checkFieldRules(
	ctx context.Context,
	pool *pgxpool.Pool,
	prefix string,
	includeShared bool,
	body []byte,
) (*fieldRuleViolation, error) {
	if prefix == "" && !includeShared {
		return nil, nil
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(body, &raw); err != nil {
		// Not this function's error to report: every caller has already
		// decoded the same body into its own request struct and answered its
		// own 400. Reaching here with unparseable JSON means the caller
		// changed; treating it as "nothing to check" would silently disable
		// the rules, so it is reported as an error instead.
		return nil, err
	}
	states, err := fieldRuleColumnStates(ctx, pool, prefix, includeShared)
	if err != nil {
		return nil, err
	}

	// Map iteration order is random, so the columns are sorted before they are
	// reported: a body breaking two rules must always name the same one, or
	// the operator sees a different error every time they press Save. Hidden
	// is reported before required because it is the injection case — a client
	// sending a switched-off field is doing something more wrong than one
	// leaving a box empty.
	for _, want := range []string{"hidden", "required"} {
		for _, col := range sortedColumns(states, want) {
			val, present := raw[col]
			if !present {
				continue
			}
			blank := isBlankJSONValue(val)
			if want == "hidden" && !blank {
				return &fieldRuleViolation{
					Code:   "field_hidden_by_rule",
					Column: col,
					Message: "The field \"" + col + "\" is switched off for this role, " +
						"so it cannot be saved. Turn it back on in Field Rules first.",
				}, nil
			}
			if want == "required" && blank {
				return &fieldRuleViolation{
					Code:   "field_required_by_rule",
					Column: col,
					Message: "\"" + col + "\" is required for this role. " +
						"Fill it in, or mark the field optional in Field Rules.",
				}, nil
			}
		}
	}
	return nil, nil
}

// sortedColumns returns the columns in `states` holding `want`, in a stable
// (alphabetical) order, so two violations in one body always report the same
// one.
func sortedColumns(states map[string]string, want string) []string {
	out := make([]string, 0, len(states))
	for col, state := range states {
		if state == want {
			out = append(out, col)
		}
	}
	// Insertion sort over a short slice — no import for six elements.
	for i := 1; i < len(out); i++ {
		for j := i; j > 0 && out[j] < out[j-1]; j-- {
			out[j], out[j-1] = out[j-1], out[j]
		}
	}
	return out
}

// isBlankJSONValue treats JSON null, an absent-ish empty string, and a
// whitespace-only string as blank. A number or a boolean is never blank: `0`
// and `false` are answers, not omissions, and refusing them would make
// `family_size: 0` unsavable.
func isBlankJSONValue(v json.RawMessage) bool {
	trimmed := strings.TrimSpace(string(v))
	if trimmed == "null" || trimmed == "" {
		return true
	}
	var s string
	if err := json.Unmarshal(v, &s); err != nil {
		return false // not a string at all
	}
	return strings.TrimSpace(s) == ""
}

// denyFieldRuleViolation writes the refusal in the same error envelope the
// rest of the admin API uses, and reports true so the caller can return.
func denyFieldRuleViolation(c *gin.Context, v *fieldRuleViolation) bool {
	if v == nil {
		return false
	}
	c.JSON(http.StatusBadRequest, gin.H{
		"success": false,
		"code":    v.Code,
		"field":   v.Column,
		"error":   v.Message,
	})
	return true
}

// guardFieldRules is the one call site shape both admin write endpoints use:
// it loads the rules, checks the body, and writes the refusal itself.
//
// A DATABASE FAILURE HERE DOES NOT BLOCK THE WRITE. The rules are form
// configuration; if they cannot be read, the endpoint's own validation still
// stands and the alternative — refusing every profile edit in the dashboard
// because one auxiliary SELECT failed — is worse than applying the edit
// unchecked. The error is surfaced to the caller so it is not swallowed.
func guardFieldRules(c *gin.Context, pool *pgxpool.Pool, prefix string, includeShared bool, body []byte) bool {
	v, err := checkFieldRules(c.Request.Context(), pool, prefix, includeShared, body)
	if err != nil {
		// Logged, not fatal — see the note above. gin's own error list is the
		// project's channel for "handled, but somebody should know".
		_ = c.Error(err)
		return false
	}
	return denyFieldRuleViolation(c, v)
}
