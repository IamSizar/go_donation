// Package permissions implements the Phase 6 dashboard access model: a small
// set of staff tiers with per-module/per-action permissions.
//
// Design: each tier has a built-in DEFAULT for every action; the
// role_permissions table stores only OVERRIDES (a Super Admin toggling a
// specific tier+module+action). The effective answer is:
//
//	Allowed = override(tier, module, action)   if a row exists
//	        = default(tier, action)            otherwise
//
// super_admin is always allowed and is never stored as overridable.
package permissions

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Tier is a dashboard staff access tier, highest to lowest privilege.
type Tier string

const (
	TierSuperAdmin Tier = "super_admin"
	TierAdmin      Tier = "admin"
	TierSupervisor Tier = "supervisor"
	TierEmployee   Tier = "employee"
	TierUser       Tier = "user"
)

// Actions a tier can perform on a module.
const (
	ActionView    = "view"
	ActionAdd     = "add"
	ActionEdit    = "edit"
	ActionArchive = "archive"
	ActionDelete  = "delete"
	ActionExport  = "export"
)

// TierFrom normalizes a raw string (or empty) to a known tier, defaulting to
// the least-privileged 'user'.
func TierFrom(s string) Tier {
	switch Tier(s) {
	case TierSuperAdmin, TierAdmin, TierSupervisor, TierEmployee:
		return Tier(s)
	default:
		return TierUser
	}
}

// CanAccessDashboard is the A-19 gate: only staff tiers may reach the admin
// dashboard at all. Plain app users (donors/beneficiaries/volunteers) can't.
func CanAccessDashboard(tier Tier) bool {
	return tier == TierSuperAdmin || tier == TierAdmin ||
		tier == TierSupervisor || tier == TierEmployee
}

// defaultAllowed is the built-in baseline for a tier+action, before any
// role_permissions override. Kept module-agnostic; the override table adds the
// per-module nuance a Super Admin configures.
func defaultAllowed(tier Tier, action string) bool {
	switch tier {
	case TierSuperAdmin, TierAdmin:
		// Admins do everything by default. (Permissions-management itself is
		// guarded separately and restricted to super_admin.)
		return true
	case TierSupervisor:
		switch action {
		case ActionView, ActionAdd, ActionEdit, ActionArchive, ActionExport:
			return true
		default: // delete
			return false
		}
	case TierEmployee:
		switch action {
		case ActionView, ActionEdit:
			return true
		default:
			return false
		}
	default: // user
		return false
	}
}

// Store answers permission questions against the role_permissions override
// table.
type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Allowed reports whether a tier may perform action on module, honoring any
// stored override and falling back to the tier default.
func (s *Store) Allowed(ctx context.Context, tier Tier, module, action string) (bool, error) {
	if tier == TierSuperAdmin {
		return true, nil
	}
	var override bool
	err := s.Pool.QueryRow(ctx,
		`SELECT allowed FROM role_permissions WHERE tier=$1 AND module=$2 AND action=$3`,
		string(tier), module, action,
	).Scan(&override)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return defaultAllowed(tier, action), nil
		}
		return false, err
	}
	return override, nil
}
