package volunteers

import (
	"strings"
	"sync"
)

// customSkillKeys holds admin-added profession keys (Section 13). It augments
// the built-in catalogue so FilterSkillKeys accepts them too. Populated at
// startup from the custom_professions table and updated when a new profession
// is added. Guarded by a RWMutex because reads happen on every save.
var (
	customSkillMu   sync.RWMutex
	customSkillKeys = map[string]struct{}{}
)

// RegisterCustomSkillKeys marks extra keys as valid volunteer skills. Idempotent.
func RegisterCustomSkillKeys(keys ...string) {
	customSkillMu.Lock()
	defer customSkillMu.Unlock()
	for _, k := range keys {
		k = strings.ToLower(strings.TrimSpace(k))
		if k != "" {
			customSkillKeys[k] = struct{}{}
		}
	}
}

// isKnownSkill reports whether a key is either a built-in or a registered
// custom profession.
func isKnownSkill(k string) bool {
	if _, ok := skillKeySet[k]; ok {
		return true
	}
	customSkillMu.RLock()
	_, ok := customSkillKeys[k]
	customSkillMu.RUnlock()
	return ok
}

// SkillKeys is the canonical 28-key catalogue. The volunteer mobile form
// renders one chip per key (in 4 languages), and the admin SPA filters by
// these same keys. Keep this list in lock-step with:
//   - humanitarian/lib/data/skill_catalogue.dart
//   - admin-web/src/lib/skillCatalogue.ts
//
// Adding a key here without updating the other two won't break anything
// (unknown keys just fall through the UI), but the chip won't render.
var SkillKeys = []string{
	// transport
	"driver_car", "driver_truck", "motorcycle",
	// trades
	"electrician", "plumber", "carpenter", "mason", "mechanic",
	// medical
	"first_aid", "nurse", "doctor", "mental_health", "eldercare",
	// service
	"cook", "cleaner", "tailor",
	// office / digital
	"designer", "photographer", "videographer",
	"social_media", "it_support", "data_entry",
	// teaching / language
	"teacher", "translator_ar", "translator_en", "counselor",
	// field work
	"distribution", "survey", "logistics", "warehouse",
}

var skillKeySet = func() map[string]struct{} {
	m := make(map[string]struct{}, len(SkillKeys))
	for _, k := range SkillKeys {
		m[k] = struct{}{}
	}
	return m
}()

// FilterSkillKeys returns only entries that match the canonical catalogue,
// deduped, lowercased, trimmed. Order is preserved relative to the input
// (first occurrence wins) — useful when the volunteer reorders their chips.
func FilterSkillKeys(raw []string) []string {
	seen := make(map[string]struct{}, len(raw))
	out := make([]string, 0, len(raw))
	for _, s := range raw {
		k := strings.ToLower(strings.TrimSpace(s))
		if k == "" {
			continue
		}
		if !isKnownSkill(k) {
			continue
		}
		if _, dup := seen[k]; dup {
			continue
		}
		seen[k] = struct{}{}
		out = append(out, k)
	}
	return out
}

// validDays = ISO-style 3-letter day-of-week keys. Matches the CHECK on
// volunteer_application_availability.day_of_week.
var validDays = map[string]struct{}{
	"mon": {}, "tue": {}, "wed": {}, "thu": {},
	"fri": {}, "sat": {}, "sun": {},
}

// DaySchedule is one row in the per-day availability table.
type DaySchedule struct {
	Day      string `json:"day"`  // mon | tue | ... | sun
	TimeFrom string `json:"from"` // HH:MM (24h)
	TimeTo   string `json:"to"`
}

// NormalizeSchedule trims/lowercases the day, validates the HH:MM shape,
// drops invalid rows, and dedupes by day (last value wins because if the
// client sends two entries for "mon" we treat the later one as the
// volunteer's correction).
func NormalizeSchedule(in []DaySchedule) []DaySchedule {
	byDay := make(map[string]DaySchedule, len(in))
	order := make([]string, 0, len(in))
	for _, d := range in {
		key := strings.ToLower(strings.TrimSpace(d.Day))
		if _, ok := validDays[key]; !ok {
			continue
		}
		from := strings.TrimSpace(d.TimeFrom)
		to := strings.TrimSpace(d.TimeTo)
		if !isHHMM(from) || !isHHMM(to) {
			continue
		}
		if from >= to {
			// "9am to 9am" or reversed range — drop it. The volunteer can
			// still tap the day off entirely if they meant "unavailable".
			continue
		}
		if _, exists := byDay[key]; !exists {
			order = append(order, key)
		}
		byDay[key] = DaySchedule{Day: key, TimeFrom: from, TimeTo: to}
	}
	out := make([]DaySchedule, 0, len(order))
	for _, k := range order {
		out = append(out, byDay[k])
	}
	return out
}

// isHHMM checks the "09:00" shape without pulling in time.Parse — cheaper
// and we never need the actual Time value here, just a sanity gate.
func isHHMM(s string) bool {
	if len(s) != 5 || s[2] != ':' {
		return false
	}
	for i, ch := range s {
		if i == 2 {
			continue
		}
		if ch < '0' || ch > '9' {
			return false
		}
	}
	hh := (int(s[0]-'0'))*10 + int(s[1]-'0')
	mm := (int(s[3]-'0'))*10 + int(s[4]-'0')
	return hh >= 0 && hh < 24 && mm >= 0 && mm < 60
}
