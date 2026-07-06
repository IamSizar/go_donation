// Package paymentmethods backs the admin-managed donation payment methods (#19):
// an ordered, 4-language list of banks/cash/wallets with account details. The
// app fetches active methods for the donate screen. Mirrors the projectcategories
// CMS with extra per-method fields.
package paymentmethods

import (
	"context"
	"errors"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Method is one payment method with 4-language name/instructions + account info.
type Method struct {
	ID              int64  `json:"id"`
	Slug            string `json:"slug"`
	MethodType      string `json:"method_type"` // cash | bank | wallet
	NameEN          string `json:"name_en"`
	NameAR          string `json:"name_ar"`
	NameCKB         string `json:"name_ckb"`
	NameKMR         string `json:"name_kmr"`
	InstructionsEN  string `json:"instructions_en"`
	InstructionsAR  string `json:"instructions_ar"`
	InstructionsCKB string `json:"instructions_ckb"`
	InstructionsKMR string `json:"instructions_kmr"`
	AccountNumber   string `json:"account_number"`
	AccountName     string `json:"account_name"`
	DisplayOrder    int    `json:"display_order"`
	Active          bool   `json:"active"`
}

// methodTypes bounds the allowed method_type values.
var methodTypes = map[string]bool{"cash": true, "bank": true, "wallet": true}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

var slugStripRE = regexp.MustCompile(`[^a-z0-9]+`)

func slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = slugStripRE.ReplaceAllString(s, "_")
	return strings.Trim(s, "_")
}

func normalizeType(t string) string {
	t = strings.ToLower(strings.TrimSpace(t))
	if methodTypes[t] {
		return t
	}
	return "bank"
}

const cols = `id, slug, method_type, name_en, name_ar, name_ckb, name_kmr,
	instructions_en, instructions_ar, instructions_ckb, instructions_kmr,
	account_number, account_name, display_order, (active = 1)`

func scan(row interface {
	Scan(dest ...any) error
}, m *Method) error {
	return row.Scan(&m.ID, &m.Slug, &m.MethodType, &m.NameEN, &m.NameAR, &m.NameCKB, &m.NameKMR,
		&m.InstructionsEN, &m.InstructionsAR, &m.InstructionsCKB, &m.InstructionsKMR,
		&m.AccountNumber, &m.AccountName, &m.DisplayOrder, &m.Active)
}

// List returns methods in display order. activeOnly → only active (app dropdown).
func (s *Store) List(ctx context.Context, activeOnly bool) ([]Method, error) {
	where := ""
	if activeOnly {
		where = " WHERE active = 1"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT `+cols+` FROM payment_methods`+where+` ORDER BY display_order, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Method{}
	for rows.Next() {
		var m Method
		if err := scan(rows, &m); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// Add inserts a new method (slug derived from name_en when blank). New methods
// are active.
func (s *Store) Add(ctx context.Context, m Method, actorID *int64) (*Method, error) {
	m.NameEN = strings.TrimSpace(m.NameEN)
	if m.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	key := slugify(m.Slug)
	if key == "" {
		key = slugify(m.NameEN)
	}
	if key == "" {
		return nil, errors.New("could not derive a method key")
	}
	var out Method
	err := scan(s.Pool.QueryRow(ctx,
		`INSERT INTO payment_methods
		   (slug, method_type, name_en, name_ar, name_ckb, name_kmr,
		    instructions_en, instructions_ar, instructions_ckb, instructions_kmr,
		    account_number, account_name, active, created_by)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,1,$13)
		 RETURNING `+cols,
		key, normalizeType(m.MethodType), m.NameEN, strings.TrimSpace(m.NameAR),
		strings.TrimSpace(m.NameCKB), strings.TrimSpace(m.NameKMR),
		strings.TrimSpace(m.InstructionsEN), strings.TrimSpace(m.InstructionsAR),
		strings.TrimSpace(m.InstructionsCKB), strings.TrimSpace(m.InstructionsKMR),
		strings.TrimSpace(m.AccountNumber), strings.TrimSpace(m.AccountName), actorID,
	), &out)
	if err != nil {
		if strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return nil, errors.New("a method with that name already exists")
		}
		return nil, err
	}
	return &out, nil
}

// Update edits a method's names, instructions, account details, type, and active
// flag. The slug is immutable.
func (s *Store) Update(ctx context.Context, id int64, m Method) (*Method, error) {
	m.NameEN = strings.TrimSpace(m.NameEN)
	if m.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	activeInt := 0
	if m.Active {
		activeInt = 1
	}
	var out Method
	err := scan(s.Pool.QueryRow(ctx,
		`UPDATE payment_methods SET
		    method_type = $2, name_en = $3, name_ar = $4, name_ckb = $5, name_kmr = $6,
		    instructions_en = $7, instructions_ar = $8, instructions_ckb = $9, instructions_kmr = $10,
		    account_number = $11, account_name = $12, active = $13
		  WHERE id = $1
		  RETURNING `+cols,
		id, normalizeType(m.MethodType), m.NameEN, strings.TrimSpace(m.NameAR),
		strings.TrimSpace(m.NameCKB), strings.TrimSpace(m.NameKMR),
		strings.TrimSpace(m.InstructionsEN), strings.TrimSpace(m.InstructionsAR),
		strings.TrimSpace(m.InstructionsCKB), strings.TrimSpace(m.InstructionsKMR),
		strings.TrimSpace(m.AccountNumber), strings.TrimSpace(m.AccountName), activeInt,
	), &out)
	if err != nil {
		if strings.Contains(err.Error(), "no rows") {
			return nil, errors.New("payment method not found")
		}
		return nil, err
	}
	return &out, nil
}

// Reorder rewrites display_order to match the id sequence, in one transaction.
func (s *Store) Reorder(ctx context.Context, orderedIDs []int64) error {
	if len(orderedIDs) == 0 {
		return nil
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	for i, id := range orderedIDs {
		if _, err := tx.Exec(ctx,
			`UPDATE payment_methods SET display_order = $2 WHERE id = $1`, id, i+1); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// Delete removes a method. Existing donations keep their stored payment_method text.
func (s *Store) Delete(ctx context.Context, id int64) error {
	ct, err := s.Pool.Exec(ctx, `DELETE FROM payment_methods WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return errors.New("payment method not found")
	}
	return nil
}
