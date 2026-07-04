package volunteers

import (
	"context"
	"errors"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Profession is one admin-added volunteer profession/skill (Section 13).
type Profession struct {
	ID       int64  `json:"id"`
	SkillKey string `json:"skill_key"`
	Category string `json:"category"`
	LabelEN  string `json:"label_en"`
	LabelAR  string `json:"label_ar"`
	LabelCKB string `json:"label_ckb"`
	LabelKMR string `json:"label_kmr"`
}

// ProfessionStore backs the custom_professions table.
type ProfessionStore struct{ Pool *pgxpool.Pool }

func NewProfessionStore(pool *pgxpool.Pool) *ProfessionStore { return &ProfessionStore{Pool: pool} }

var slugStripRE = regexp.MustCompile(`[^a-z0-9]+`)

// slugify turns a free-text label into a canonical skill key: lowercased,
// non-alphanumeric runs collapsed to a single underscore.
func slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = slugStripRE.ReplaceAllString(s, "_")
	return strings.Trim(s, "_")
}

// List returns every custom profession, oldest first.
func (s *ProfessionStore) List(ctx context.Context) ([]Profession, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT id, skill_key, category, label_en, label_ar, label_ckb, label_kmr
		   FROM custom_professions ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Profession{}
	for rows.Next() {
		var p Profession
		if err := rows.Scan(&p.ID, &p.SkillKey, &p.Category,
			&p.LabelEN, &p.LabelAR, &p.LabelCKB, &p.LabelKMR); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// Add inserts a new profession, deriving the skill_key from the English label
// (or an explicit key if provided), then registers it as a valid skill so it
// passes FilterSkillKeys immediately. Returns the stored row.
func (s *ProfessionStore) Add(ctx context.Context, p Profession, actorID *int64) (*Profession, error) {
	p.LabelEN = strings.TrimSpace(p.LabelEN)
	if p.LabelEN == "" {
		return nil, errors.New("English label is required")
	}
	key := slugify(p.SkillKey)
	if key == "" {
		key = slugify(p.LabelEN)
	}
	if key == "" {
		return nil, errors.New("could not derive a profession key")
	}
	// A custom key must not collide with a built-in catalogue key.
	if _, ok := skillKeySet[key]; ok {
		return nil, errors.New("that profession already exists in the catalogue")
	}
	cat := strings.TrimSpace(p.Category)
	if cat == "" {
		cat = "custom"
	}
	var id int64
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO custom_professions (skill_key, category, label_en, label_ar, label_ckb, label_kmr, created_by)
		 VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
		key, cat, p.LabelEN, strings.TrimSpace(p.LabelAR),
		strings.TrimSpace(p.LabelCKB), strings.TrimSpace(p.LabelKMR), actorID,
	).Scan(&id)
	if err != nil {
		if strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return nil, errors.New("a profession with that name already exists")
		}
		return nil, err
	}
	RegisterCustomSkillKeys(key)
	p.ID = id
	p.SkillKey = key
	p.Category = cat
	return &p, nil
}

// LoadAndRegister loads every stored custom key and registers it with the skill
// validator. Call once at startup so tagging volunteers with custom professions
// survives a restart.
func (s *ProfessionStore) LoadAndRegister(ctx context.Context) error {
	items, err := s.List(ctx)
	if err != nil {
		return err
	}
	keys := make([]string, 0, len(items))
	for _, p := range items {
		keys = append(keys, p.SkillKey)
	}
	RegisterCustomSkillKeys(keys...)
	return nil
}
