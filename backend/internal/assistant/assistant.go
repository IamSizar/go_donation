// Package assistant implements the in-app AI Support Assistant.
//
// Design: provider-agnostic with graceful degradation.
//
//   - If an LLM API key is configured (ANTHROPIC_API_KEY), each user turn is
//     answered by Claude using a role-specific system prompt. The model returns
//     strict JSON {reply, route}; we parse it and attach a navigation action.
//
//   - If no key is configured, OR the LLM call fails for any reason, we fall
//     back to a deterministic keyword-intent engine over the same knowledge
//     base. The assistant therefore always returns a useful answer.
//
// The mobile app only ever sees a uniform response shape, so it doesn't need to
// know which path produced the answer (the `source` field is informational).
package assistant

import (
	"context"
	"encoding/json"
	"os"
	"sort"
	"strings"

	"github.com/karam-flutter/humanitarian-backend/internal/appsettings"
)

// Message is one turn of the conversation coming from the client.
type Message struct {
	Role    string `json:"role"`    // "user" | "assistant"
	Content string `json:"content"` // the text
}

// ToolResult is one tool call's outcome, surfaced to the client so the UI
// can render it as a structured card instead of relying purely on prose.
type ToolResult struct {
	Tool string          `json:"tool"`
	Data json.RawMessage `json:"data"`
}

// Reply is the assistant's structured answer.
type Reply struct {
	Text        string       `json:"reply"`
	Action      *Action      `json:"action,omitempty"`
	Source      string       `json:"source"` // "ai" | "local"
	ToolResults []ToolResult `json:"tool_results,omitempty"`
}

// Service answers assistant turns. Construct with New.
type Service struct {
	llm      *anthropicClient // nil when no API key configured
	deps     Deps
	settings *appsettings.Store // nil-safe; enabled/extra-instructions default when absent
}

// New builds the assistant service, reading provider config from the
// environment. With no key present, llm stays nil and the engine runs
// locally. deps wires the tool-calling path's read-only data sources.
func New(deps Deps, settings *appsettings.Store) *Service {
	svc := &Service{deps: deps, settings: settings}
	key := strings.TrimSpace(os.Getenv("ANTHROPIC_API_KEY"))
	if key == "" {
		return svc
	}
	model := strings.TrimSpace(os.Getenv("ASSISTANT_MODEL"))
	svc.llm = newAnthropicClient(key, model)
	return svc
}

// LLMEnabled reports whether a real model backs the assistant.
func (s *Service) LLMEnabled() bool { return s.llm != nil }

// enabled reports the admin "Enable AI Assistant" toggle. Defaults to true
// when unset so existing deployments keep working without a settings row.
func (s *Service) enabled(ctx context.Context) bool {
	if s.settings == nil {
		return true
	}
	v, err := s.settings.Get(ctx, appsettings.KeyAssistantEnabled)
	if err != nil {
		return true
	}
	return v != "false"
}

func (s *Service) extraInstructions(ctx context.Context) string {
	if s.settings == nil {
		return ""
	}
	v, _ := s.settings.Get(ctx, appsettings.KeyAssistantExtraInstructions)
	return v
}

// Answer produces a reply for the given role + conversation history. userID
// scopes any tool calls to that user's own data — the model never supplies
// it itself. userName may be empty. lang is the app locale ("en", "ar",
// "ckb", "kmr"); intentID is the stable chip id for chip-tap turns (empty
// for free-typed messages).
func (s *Service) Answer(ctx context.Context, roleID int, userID int64, userName string, history []Message, lang string, intentID string) Reply {
	// Try the LLM first when available and not disabled by admin.
	if s.llm != nil && s.enabled(ctx) {
		if r, ok := s.answerWithLLM(ctx, roleID, userID, userName, history, lang); ok {
			return r
		}
		// fall through to local on any failure
	}
	return s.answerLocally(roleID, history, lang, intentID)
}

// ──────────────────────────────────────────────────────────────────────────
// LLM path
// ──────────────────────────────────────────────────────────────────────────

// maxToolRounds caps how many tool round-trips one turn can make, so a model
// that keeps calling tools can never hang the request indefinitely.
const maxToolRounds = 4

// answerWithLLM calls the configured LLM, running an agentic tool-use loop:
// the model may call one of the role's tools (each scoped to userID), see
// the result, and call another — up to maxToolRounds — before giving its
// final answer. lang is injected into the system prompt so the model replies
// in the user's app language (ar / ckb / kmr / en).
func (s *Service) answerWithLLM(ctx context.Context, roleID int, userID int64, userName string, history []Message, lang string) (Reply, bool) {
	sys := systemPrompt(roleID, userName, lang, s.extraInstructions(ctx))
	tools := toolsFor(roleID)

	// Convert history to the client shape, keeping only the last ~12 turns to
	// bound token use. Drop any empty messages.
	msgs := make([]chatMessage, 0, len(history))
	for _, m := range history {
		c := strings.TrimSpace(m.Content)
		if c == "" {
			continue
		}
		role := "user"
		if m.Role == "assistant" {
			role = "assistant"
		}
		msgs = append(msgs, chatMessage{Role: role, Content: []contentBlock{textBlock(c)}})
	}
	if len(msgs) == 0 {
		return Reply{}, false
	}
	if len(msgs) > 12 {
		msgs = msgs[len(msgs)-12:]
	}
	// The Anthropic API requires the first message to be from the user.
	for len(msgs) > 0 && msgs[0].Role != "user" {
		msgs = msgs[1:]
	}
	if len(msgs) == 0 {
		return Reply{}, false
	}

	var toolResults []ToolResult
	for round := 0; round < maxToolRounds; round++ {
		resp, err := s.llm.complete(ctx, sys, tools, msgs)
		if err != nil {
			return Reply{}, false
		}

		var toolUses []contentBlock
		var text strings.Builder
		for _, block := range resp.Content {
			switch block.Type {
			case "text":
				text.WriteString(block.Text)
			case "tool_use":
				toolUses = append(toolUses, block)
			}
		}

		if len(toolUses) == 0 {
			reply, ok := parseLLMJSON(text.String(), roleID, lang)
			if !ok {
				trimmed := strings.TrimSpace(text.String())
				if trimmed == "" {
					return Reply{}, false
				}
				reply = Reply{Text: trimmed, Source: "ai"}
			}
			reply.ToolResults = toolResults
			return reply, true
		}

		// The model wants to call one or more tools. Execute them (scoped to
		// userID) and feed the results back for the next round.
		assistantBlocks := make([]contentBlock, 0, len(toolUses)+1)
		if strings.TrimSpace(text.String()) != "" {
			assistantBlocks = append(assistantBlocks, textBlock(text.String()))
		}
		assistantBlocks = append(assistantBlocks, toolUses...)
		msgs = append(msgs, chatMessage{Role: "assistant", Content: assistantBlocks})

		resultBlocks := make([]contentBlock, 0, len(toolUses))
		for _, tu := range toolUses {
			result := executeToolCall(ctx, s.deps, userID, tu.Name)
			toolResults = append(toolResults, ToolResult{Tool: tu.Name, Data: json.RawMessage(result)})
			resultBlocks = append(resultBlocks, contentBlock{
				Type: "tool_result", ToolUseID: tu.ID, Content: result,
			})
		}
		msgs = append(msgs, chatMessage{Role: "user", Content: resultBlocks})
	}

	// Hit the round cap without a final answer — fall back rather than hang.
	return Reply{}, false
}

// llmJSON is the strict shape we ask the model to emit.
type llmJSON struct {
	Reply string `json:"reply"`
	Route string `json:"route"`
}

// parseLLMJSON extracts {reply, route} from the model output. It tolerates the
// model wrapping JSON in prose or code fences by scanning for the first {...}.
func parseLLMJSON(out string, roleID int, lang string) (Reply, bool) {
	raw := extractJSONObject(out)
	if raw == "" {
		return Reply{}, false
	}
	var parsed llmJSON
	if err := json.Unmarshal([]byte(raw), &parsed); err != nil {
		return Reply{}, false
	}
	text := strings.TrimSpace(parsed.Reply)
	if text == "" {
		return Reply{}, false
	}

	r := Reply{Text: text, Source: "ai"}
	route := Route(strings.TrimSpace(parsed.Route))
	if route != "" && route != RouteNone && isAllowedRoute(roleID, route) {
		r.Action = &Action{Label: labelFor(route, lang), Route: route}
	}
	return r, true
}

// extractJSONObject returns the substring from the first '{' to the last '}'.
func extractJSONObject(s string) string {
	start := strings.IndexByte(s, '{')
	end := strings.LastIndexByte(s, '}')
	if start < 0 || end < 0 || end <= start {
		return ""
	}
	return s[start : end+1]
}

func isAllowedRoute(roleID int, r Route) bool {
	for _, a := range allowedRoutes(roleID) {
		if a == r {
			return true
		}
	}
	return false
}

func defaultLabel(r Route) string {
	switch r {
	case RouteDonate:
		return "Go to Campaigns"
	case RouteMyDonations:
		return "View My Donations"
	case RouteMarket:
		return "Open Market"
	case RouteKafala:
		return "Open Kafala"
	case RouteSubmitProject:
		return "Submit a Project"
	case RoutePendingProjects:
		return "Pending Projects"
	case RouteCampaignDonations:
		return "My Campaign Donations"
	case RouteCommunity:
		return "Open Community"
	case RouteAlerts:
		return "Go to Alerts"
	case RouteProfile:
		return "Open Profile"
	case RouteEditProfile:
		return "Edit Profile"
	case RouteVolunteer:
		return "Open Volunteer"
	case RouteServices:
		return "Open Services"
	case RouteMarriage:
		return "Open Marriage Form"
	case RouteMessages:
		return "Open Messages"
	case RouteSupport:
		return "Contact Support"
	case RouteHome:
		return "Go Home"
	default:
		return "Open"
	}
}

// labelFor returns the CTA button label for a route in the given language.
// English falls through to defaultLabel (preserving the exact existing wording);
// ar/ckb/kmr come from localizedLabels, defaulting to English for any gap.
func labelFor(r Route, lang string) string {
	if lang != "" && lang != "en" {
		if byRoute, ok := localizedLabels[r]; ok {
			if l := byRoute[lang]; l != "" {
				return l
			}
		}
	}
	return defaultLabel(r)
}

// localizedLabels holds CTA labels per route per language (ar / ckb / kmr).
var localizedLabels = map[Route]map[string]string{
	RouteDonate: {
		"ar": "اذهب إلى الحملات", "ckb": "بڕۆ بۆ کامپەینەکان", "kmr": "هەرە بۆ کامپینان",
	},
	RouteMyDonations: {
		"ar": "عرض تبرعاتي", "ckb": "بینینی بەخشینەکانم", "kmr": "بەخشینێن من ببینە",
	},
	RouteMarket: {
		"ar": "افتح السوق", "ckb": "بازاڕ بکەوە", "kmr": "بازارێ ڤەکە",
	},
	RouteKafala: {
		"ar": "افتح الكفالة", "ckb": "کەفالە بکەوە", "kmr": "کەفالە ڤەکە",
	},
	RouteSubmitProject: {
		"ar": "قدّم مشروعاً", "ckb": "پڕۆژەیەک تەقدیم بکە", "kmr": "پرۆژەیەکێ بنێرە",
	},
	RoutePendingProjects: {
		"ar": "المشاريع المعلقة", "ckb": "پڕۆژە هەڵواسراوەکان", "kmr": "پرۆژەیێن چاڤەڕوانیێ",
	},
	RouteCampaignDonations: {
		"ar": "تبرعات حملتي", "ckb": "بەخشینی کامپەینەکانم", "kmr": "بەخشینێن کامپینێن من",
	},
	RouteCommunity: {
		"ar": "افتح المجتمع", "ckb": "کۆمەڵگا بکەوە", "kmr": "جڤاکێ ڤەکە",
	},
	RouteAlerts: {
		"ar": "اذهب إلى التنبيهات", "ckb": "بڕۆ بۆ ئاگادارکردنەوەکان", "kmr": "هەرە بۆ ئاگەهداریان",
	},
	RouteProfile: {
		"ar": "افتح الملف الشخصي", "ckb": "پرۆفایل بکەوە", "kmr": "پرۆفایلێ ڤەکە",
	},
	RouteEditProfile: {
		"ar": "تعديل الملف الشخصي", "ckb": "دەستکاری پرۆفایل", "kmr": "دەستکاریا پرۆفایلێ",
	},
	RouteVolunteer: {
		"ar": "افتح التطوع", "ckb": "ڕاهێنان بکەوە", "kmr": "خۆبەخشیێ ڤەکە",
	},
	RouteServices: {
		"ar": "افتح الخدمات", "ckb": "خزمەتگوزارییەکان بکەوە", "kmr": "خزمەتگوزاریان ڤەکە",
	},
	RouteMarriage: {
		"ar": "افتح نموذج الزواج", "ckb": "فۆرمی زەواج بکەوە", "kmr": "فۆرما هاوسەرگیریێ ڤەکە",
	},
	RouteMessages: {
		"ar": "افتح الرسائل", "ckb": "پەیامەکان بکەوە", "kmr": "پەیاما ڤەکە",
	},
	RouteSupport: {
		"ar": "اتصل بالدعم", "ckb": "پەیوەندی بە پشتگیری", "kmr": "پەیوەندی ب پشتگیریێ",
	},
	RouteHome: {
		"ar": "اذهب إلى الرئيسية", "ckb": "بڕۆ بۆ سەرەتا", "kmr": "هەرە بۆ سەرەکی",
	},
}

// ──────────────────────────────────────────────────────────────────────────
// Local fallback path — keyword intent scoring
// ──────────────────────────────────────────────────────────────────────────

// answerLocally runs the keyword-intent engine with full i18n support.
//
//  1. If intentID is set (chip tap), resolve the intent by stable id directly —
//     no keyword matching needed, works in any language.
//  2. Otherwise keyword-score using the language-appropriate keyword list.
//  3. Answer text is returned via answerFor(lang) so AR/CKB/KMR users see their
//     own language; English is the fallback when a translation is absent.
func (s *Service) answerLocally(roleID int, history []Message, lang string, intentID string) Reply {
	intents := intentsFor(roleID)

	// ── Task 6: id-first resolution ──────────────────────────────────────────
	// A chip tap sends a stable id (e.g. "d_donate"). Match it directly so we
	// never need keyword matching in foreign languages for chip taps.
	if intentID != "" {
		for _, it := range intents {
			if it.ID == intentID {
				return Reply{Text: it.answerFor(lang), Action: localizeAction(it.Action, lang), Source: "local"}
			}
		}
	}

	// ── Free-typed input: keyword scoring ────────────────────────────────────
	query := ""
	for i := len(history) - 1; i >= 0; i-- {
		if history[i].Role != "assistant" {
			query = history[i].Content
			break
		}
	}
	query = strings.ToLower(strings.TrimSpace(query))

	if query == "" {
		return greeting(lang)
	}

	// Score every intent using the keyword list for the user's language.
	// Longer keyword phrases score higher so specific matches win.
	type scored struct {
		intent Intent
		score  int
	}
	ranked := make([]scored, 0, len(intents))
	for _, it := range intents {
		score := 0
		for _, k := range it.keywordsFor(lang) {
			if strings.Contains(query, k) {
				score += 1 + strings.Count(k, " ") // multiword bonus
			}
		}
		if score > 0 {
			ranked = append(ranked, scored{intent: it, score: score})
		}
	}

	if len(ranked) == 0 {
		return fallbackReply(lang)
	}

	sort.SliceStable(ranked, func(i, j int) bool { return ranked[i].score > ranked[j].score })
	best := ranked[0].intent
	return Reply{Text: best.answerFor(lang), Action: localizeAction(best.Action, lang), Source: "local"}
}

// localizeAction returns a copy of a with its label translated for lang.
// Returns a unchanged for nil or English (preserving the exact act() wording).
func localizeAction(a *Action, lang string) *Action {
	if a == nil || lang == "" || lang == "en" {
		return a
	}
	return &Action{Label: labelFor(a.Route, lang), Route: a.Route}
}

func greeting(lang string) Reply {
	text := "Hi! I'm your Support Assistant. Ask me how to do anything in the app — " +
		"like how to donate, track a request, or chat with someone — and I'll guide you."
	switch lang {
	case "ar":
		text = "مرحباً! أنا مساعد الدعم الخاص بك. اسألني كيفية القيام بأي شيء في التطبيق — مثل كيفية التبرع، تتبع طلب، أو التواصل مع شخص ما — وسأرشدك."
	case "ckb":
		text = "سڵاو! من یاریدەدەری پشتگیریتم. لێم بپرسە چۆن هەر شتێک لە ئەپەکە بکەیت — وەک چۆن بەخشین بکەیت، داواکارییەکی شوێن بکەیت، یان لەگەڵ کەسێکدا گفتوگۆ بکەیت — و ئاڕاستەت دەکەم."
	case "kmr":
		text = "سلاڤ! ئەز هاریکارێ پشتگیریا تەمە. ژ من بپرسە چەوا هەر تشتەکی د ئەپی دا بکەم — وەک چەوا ببەخشم، داخوازەکێ بشوپینم، یان دگەل کەسەکی ئاخفتنێ بکەم — و ئەز دێ تە رێنمایی کەم."
	}
	return Reply{Text: text, Source: "local"}
}

func fallbackReply(lang string) Reply {
	text := "I'm not totally sure about that one, but our support team can help directly. " +
		"You can reach them from the Services section — or try rephrasing your question and I'll do my best."
	switch lang {
	case "ar":
		text = "لست متأكداً تماماً من ذلك، لكن فريق الدعم يمكنه المساعدة مباشرة. يمكنك التواصل معهم من قسم الخدمات — أو حاول إعادة صياغة سؤالك وسأبذل قصارى جهدي."
	case "ckb":
		text = "دڵنیام نیە بۆ ئەوە، بەڵام تیمی پشتگیریمان دەتوانێت ڕاستەوخۆ یارمەتی بدات. دەتوانیت لە بەشی خزمەتگوزارییەکانەوە پەیوەندیان پێوە بکەیت — یان هەوڵبدە پرسیارەکەت دووبارە بنووسیت و من هەموو هەوڵێکم دەدەم."
	case "kmr":
		text = "ئەز ب تەمامی نە دڵنیام ژ وێ، بەلێ تیمێ پشتگیریا مە دشێت رەستەوخۆ هاریکاریێ بدەت. تو دشێی ژ بەشا خزمەتگوزاریان پەیوەندیێ دگەل وان بکەی — یان هەول بدە پرسیارا خۆ ژ نوی ڤە بنڤیسی و ئەز دێ هەمی هەولا خۆ دەم."
	}
	return Reply{
		Text:   text,
		Action: &Action{Label: labelFor(RouteSupport, lang), Route: RouteSupport},
		Source: "local",
	}
}
