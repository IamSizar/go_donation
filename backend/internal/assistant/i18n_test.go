package assistant

import (
	"strings"
	"testing"
)

// newLocalService builds a Service with no LLM so Answer() always takes the
// local keyword/id engine — the path we verify here.
func newLocalService() *Service { return &Service{} }

// roleDonor is the numeric role id for a donor (intentsFor default).
const roleDonor = 1

func userMsg(text string) []Message { return []Message{{Role: "user", Content: text}} }

// Task 16: chip tap (intent id) resolves to the localized answer + label,
// independent of language, for every supported locale.
func TestLocal_IntentIDResolvesLocalizedAnswer(t *testing.T) {
	svc := newLocalService()

	cases := []struct {
		lang        string
		wantInReply string // a distinctive substring of the localized answer
		wantLabel   string // localized CTA label
	}{
		{"en", "open the Donate", "Go to Campaigns"},
		{"ar", "افتح تبويب التبرع", "اذهب إلى الحملات"},
		{"ckb", "تابی بەخشین", "بڕۆ بۆ کامپەینەکان"},
		{"kmr", "تابا بەخشینێ", "هەرە بۆ کامپینان"},
	}

	for _, c := range cases {
		// Empty message body — resolution must come purely from the intent id.
		got := svc.Answer(nil, roleDonor, "", userMsg(""), c.lang, "d_donate")
		if !strings.Contains(got.Text, c.wantInReply) {
			t.Errorf("[%s] reply %q does not contain %q", c.lang, got.Text, c.wantInReply)
		}
		if got.Action == nil {
			t.Fatalf("[%s] expected an action, got nil", c.lang)
		}
		if got.Action.Label != c.wantLabel {
			t.Errorf("[%s] label = %q, want %q", c.lang, got.Action.Label, c.wantLabel)
		}
		if got.Action.Route != RouteDonate {
			t.Errorf("[%s] route = %q, want donate", c.lang, got.Action.Route)
		}
		if got.Source != "local" {
			t.Errorf("[%s] source = %q, want local", c.lang, got.Source)
		}
	}
}

// Task 16: free-typed input matches via the language-appropriate keyword list.
func TestLocal_KeywordMatchPerLanguage(t *testing.T) {
	svc := newLocalService()

	cases := []struct {
		lang  string
		query string
		want  string // distinctive substring of the expected localized answer
	}{
		{"en", "how do I donate?", "open the Donate"},
		{"ar", "كيف أتبرع للحملة", "افتح تبويب التبرع"},
		{"ckb", "چۆن بەخشیم", "تابی بەخشین"},
		{"kmr", "ئەز چەوا ببەخشم", "تابا بەخشینێ"},
	}

	for _, c := range cases {
		got := svc.Answer(nil, roleDonor, "", userMsg(c.query), c.lang, "")
		if !strings.Contains(got.Text, c.want) {
			t.Errorf("[%s] query %q → reply %q, want substring %q", c.lang, c.query, got.Text, c.want)
		}
	}
}

// Task 16: an unmatched query returns the localized fallback + support action.
func TestLocal_FallbackReplyLocalized(t *testing.T) {
	svc := newLocalService()
	gibberish := "zzzqqq xkcd 9999"

	checks := map[string]string{
		"en":  "not totally sure",
		"ar":  "لست متأكداً",
		"ckb": "دڵنیام نیە",
		"kmr": "نە دڵنیام",
	}
	for lang, want := range checks {
		got := svc.Answer(nil, roleDonor, "", userMsg(gibberish), lang, "")
		if !strings.Contains(got.Text, want) {
			t.Errorf("[%s] fallback %q missing %q", lang, got.Text, want)
		}
		if got.Action == nil || got.Action.Route != RouteSupport {
			t.Errorf("[%s] expected support action, got %+v", lang, got.Action)
		}
	}
}

// Task 15: the system prompt injects a hard language directive for non-English
// locales (and none for English), so the LLM replies in the user's language.
func TestSystemPrompt_LanguageDirective(t *testing.T) {
	if got := systemPrompt(roleDonor, "", "en"); strings.Contains(got, "MUST be written entirely") {
		t.Error("English prompt should not contain a language directive")
	}
	cases := map[string]string{
		"ar":  "Arabic",
		"ckb": "Kurdish Sorani",
		"kmr": "Kurdish Behdini",
	}
	for lang, want := range cases {
		got := systemPrompt(roleDonor, "", lang)
		// The directive must lead the prompt (so it isn't overridden) ...
		if !strings.HasPrefix(strings.TrimSpace(got), "IMPORTANT: The \"reply\" text MUST be written entirely in "+want) {
			t.Errorf("[%s] prompt should open with the %s directive; got prefix %q", lang, want, firstLine(got))
		}
		// ... and be repeated as a closing reminder so it stays salient.
		if !strings.Contains(got, "Remember: the \"reply\" value must be in") {
			t.Errorf("[%s] prompt should end with a language reminder", lang)
		}
	}
}

// Task 15: the LLM JSON parser attaches a localized label for the chosen route.
func TestParseLLMJSON_LocalizedLabel(t *testing.T) {
	out := `{"reply": "تفضل", "route": "edit_profile"}`
	got, ok := parseLLMJSON(out, roleDonor, "ar")
	if !ok {
		t.Fatal("expected parse to succeed")
	}
	if got.Action == nil || got.Action.Label != "تعديل الملف الشخصي" {
		t.Errorf("ar label = %+v, want تعديل الملف الشخصي", got.Action)
	}
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}
