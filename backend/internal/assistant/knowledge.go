package assistant

import "strings"

// This file holds the assistant's knowledge of the app. It serves two roles:
//
//   1. As the SYSTEM PROMPT for the LLM (when an API key is configured) — the
//      role-specific capability description tells Claude exactly what the app
//      can do and which navigation routes exist.
//
//   2. As the INTENT TABLE for the offline fallback engine (when no key is set)
//      — keyword scoring over the same intents produces a helpful answer plus a
//      navigation action, so the assistant is useful even without an LLM.
//
// Keeping both in one place means the LLM and the fallback never drift apart.

// Route is a stable key the mobile app maps to a dashboard tab. The backend
// stays ignorant of Flutter tab indices; it only emits these keys.
type Route string

const (
	RouteNone      Route = "none"
	RouteHome      Route = "home"
	RouteDonate    Route = "donate"
	RouteMarket    Route = "market"
	RouteKafala    Route = "kafala"
	RouteCommunity Route = "community"
	RouteAlerts    Route = "alerts"
	RouteProfile   Route = "profile"
	RouteVolunteer Route = "volunteer"
	RouteServices  Route = "services"
	RouteMessages  Route = "messages"

	// Deep routes — the mobile app opens a SPECIFIC screen, not just a tab.
	RouteMyDonations       Route = "my_donations"       // → My Donations list
	RouteEditProfile       Route = "edit_profile"       // → Edit Profile form
	RouteSubmitProject     Route = "submit_project"     // → Submit New Project
	RoutePendingProjects   Route = "pending_projects"   // → Pending Projects
	RouteCampaignDonations Route = "campaign_donations" // → My Campaign Donations
	RouteMarriage          Route = "marriage"           // → Marriage support form
	RouteSupport           Route = "support"            // → Support ticket form
)

// Action is the optional CTA attached to a reply.
type Action struct {
	Label string `json:"label"`
	Route Route  `json:"route"`
}

// Intent is one fallback-engine entry: keywords → answer + optional action.
type Intent struct {
	ID          string              // stable key matching the client's BotQA.id
	Keywords    []string            // English keywords (default)
	KeywordsMap map[string][]string // per-language keywords: "ar", "ckb", "kmr"
	Answer      string              // English answer (default)
	Answers     map[string]string   // per-language answers: "ar", "ckb", "kmr"
	Action      *Action
}

// answerFor returns the localised answer for lang, falling back to English.
func (it Intent) answerFor(lang string) string {
	if lang != "" && lang != "en" && it.Answers != nil {
		if a := it.Answers[lang]; a != "" {
			return a
		}
	}
	return it.Answer
}

// keywordsFor returns the keyword list for lang, falling back to English.
func (it Intent) keywordsFor(lang string) []string {
	if lang != "" && lang != "en" && it.KeywordsMap != nil {
		if kw := it.KeywordsMap[lang]; len(kw) > 0 {
			return kw
		}
	}
	return it.Keywords
}

func act(label string, r Route) *Action { return &Action{Label: label, Route: r} }

// ──────────────────────────────────────────────────────────────────────────
// Role resolution
// ──────────────────────────────────────────────────────────────────────────

// roleName maps the numeric role id to a human label used in prompts.
func roleName(roleID int) string {
	switch roleID {
	case 2:
		return "Eligible"
	case 3:
		return "Volunteer"
	default:
		return "Grantor"
	}
}

// intentsFor returns the fallback intent table for a role, with the shared
// "about the app" intents appended so every role can answer what the app does.
func intentsFor(roleID int) []Intent {
	var base []Intent
	switch roleID {
	case 2:
		base = beneficiaryIntents
	case 3:
		base = volunteerIntents
	default:
		base = donorIntents
	}
	out := make([]Intent, 0, len(base)+len(aboutAppIntents))
	out = append(out, base...)
	out = append(out, aboutAppIntents...)
	return out
}

// allowedRoutes lists the navigation routes that make sense for a role. The
// LLM is told to only emit one of these.
func allowedRoutes(roleID int) []Route {
	switch roleID {
	case 2:
		return []Route{
			RouteKafala, RouteSubmitProject, RoutePendingProjects, RouteCampaignDonations,
			RouteCommunity, RouteAlerts, RouteProfile, RouteEditProfile, RouteServices,
			RouteMarriage, RouteMessages, RouteSupport, RouteNone,
		}
	case 3:
		return []Route{
			RouteVolunteer, RouteCommunity, RouteAlerts, RouteProfile, RouteEditProfile,
			RouteServices, RouteSupport, RouteNone,
		}
	default:
		return []Route{
			RouteDonate, RouteMyDonations, RouteMarket, RouteKafala, RouteCommunity,
			RouteAlerts, RouteProfile, RouteEditProfile, RouteServices, RouteMarriage,
			RouteMessages, RouteSupport, RouteNone,
		}
	}
}

// ──────────────────────────────────────────────────────────────────────────
// System prompt (LLM)
// ──────────────────────────────────────────────────────────────────────────

// langInstruction returns the language directive injected at the top of the
// system prompt. Returns "" for English (model default — no instruction needed).
func langInstruction(lang string) string {
	switch lang {
	case "ar":
		return "IMPORTANT: The \"reply\" text MUST be written entirely in Arabic (العربية), " +
			"regardless of which language the user writes in. Even if the user types in English or " +
			"Kurdish, you reply in Arabic. Do not mix in any other language."
	case "ckb":
		return "IMPORTANT: The \"reply\" text MUST be written entirely in Kurdish Sorani / Central " +
			"Kurdish (کوردیی سۆرانی), regardless of which language the user writes in. Even if the user " +
			"types in English or Arabic, you reply in Sorani. Do NOT use the Badini/Kurmanji dialect. " +
			"Do not mix in any other language."
	case "kmr":
		return "IMPORTANT: The \"reply\" text MUST be written entirely in Kurdish Behdini / Badini in the " +
			"ARABIC script (کوردیی بادینی) — for example 'سلاڤ، چەوانی؟ باشم، سوپاس'. Reply in Behdini " +
			"regardless of which language the user writes in. Do NOT use Latin letters and do NOT use the " +
			"Sorani dialect; use the Behdini (Kurmanji) dialect in Arabic script. Do not mix in any other language."
	default:
		return "" // English is the model default; no directive needed.
	}
}

// langReminder is a short closing nudge appended after the output-format block.
// Models weight the most recent instruction heavily, so repeating the language
// requirement next to the JSON spec makes the reply-language far more reliable.
func langReminder(lang string) string {
	switch lang {
	case "ar":
		return "Remember: the \"reply\" value must be in Arabic."
	case "ckb":
		return "Remember: the \"reply\" value must be in Kurdish Sorani (سۆرانی)."
	case "kmr":
		return "Remember: the \"reply\" value must be in Kurdish Behdini/Badini in Arabic script (بادینی)."
	default:
		return ""
	}
}

// systemPrompt builds the instruction block sent to the LLM. It encodes the
// app's capabilities for the user's role, the routing contract, the strict-JSON
// output format, and — when lang is not English — a language directive that
// instructs the model to reply in the user's app language. extraInstructions
// is optional admin-configured text (Settings → AI Assistant) appended near
// the end, so staff can nudge tone/scope without a redeploy.
func systemPrompt(roleID int, userName string, lang string, extraInstructions string) string {
	var b strings.Builder

	// Language override first — the model must see this before any other
	// instruction so it isn't overridden by the English prose that follows.
	if inst := langInstruction(lang); inst != "" {
		b.WriteString(inst + "\n\n")
	}

	b.WriteString("You are the in-app Support Assistant for a humanitarian aid mobile app. ")
	b.WriteString("You help users understand and navigate the app. Be warm, concise, and practical. ")
	b.WriteString("Answer in 2–5 short sentences. Never invent features that are not listed below.\n\n")

	if userName != "" {
		b.WriteString("The user's name is " + userName + ". ")
	}
	b.WriteString("The user's role is: " + roleName(roleID) + ".\n\n")

	b.WriteString("APP CAPABILITIES FOR THIS ROLE:\n")
	b.WriteString(capabilityText(roleID))
	b.WriteString("\n")

	b.WriteString("NAVIGATION ROUTES you may suggest (use the exact key):\n")
	for _, r := range allowedRoutes(roleID) {
		if r == RouteNone {
			continue
		}
		b.WriteString("  - " + string(r) + ": " + routeDescription(r) + "\n")
	}
	b.WriteString("\n")

	b.WriteString("You also have TOOLS to look up the user's own real data (wallet balance, ")
	b.WriteString("donations, marriage profile, case/project status, or volunteer status — whichever ")
	b.WriteString("apply to their role). ALWAYS call the relevant tool before answering a question about ")
	b.WriteString("the user's own personal data — never guess, estimate, or invent a number or status. ")
	b.WriteString("If a tool returns an error, tell the user you couldn't retrieve that information right ")
	b.WriteString("now rather than making something up. Call tools first, THEN give your final answer in ")
	b.WriteString("the JSON format below — don't emit the JSON in the same turn as a tool call.\n\n")

	if extra := strings.TrimSpace(extraInstructions); extra != "" {
		b.WriteString("ADDITIONAL STAFF INSTRUCTIONS (from the admin dashboard):\n" + extra + "\n\n")
	}

	b.WriteString("OUTPUT FORMAT — respond with ONLY a single JSON object, no markdown, no prose around it:\n")
	b.WriteString(`{"reply": "<your helpful answer>", "route": "<one route key from the list, or none>"}` + "\n")
	b.WriteString("Set route to the screen that best lets the user act on your answer, or \"none\" if no navigation helps. ")
	b.WriteString("If the question is unrelated to the app, gently steer back and set route to \"support\".\n")

	// Repeat the language requirement last so it stays salient when the model
	// generates the reply text.
	if rem := langReminder(lang); rem != "" {
		b.WriteString(rem + "\n")
	}

	return b.String()
}

// routeDescription gives the LLM a one-line meaning for each route key.
func routeDescription(r Route) string {
	switch r {
	case RouteDonate:
		return "browse active campaigns and donate"
	case RouteMyDonations:
		return "opens the user's own donation history & details screen directly"
	case RouteMarket:
		return "the eligible marketplace to buy products"
	case RouteKafala:
		return "the Kafala sponsorship hub"
	case RouteSubmitProject:
		return "opens the Submit New Project form directly"
	case RoutePendingProjects:
		return "opens the Pending Projects screen directly"
	case RouteCampaignDonations:
		return "opens the My Campaign Donations screen directly (grantors who gave to your campaigns)"
	case RouteCommunity:
		return "community guides, city map, partner organisations"
	case RouteAlerts:
		return "notifications and alerts"
	case RouteProfile:
		return "the user's profile tab"
	case RouteEditProfile:
		return "opens the Edit Profile form directly"
	case RouteVolunteer:
		return "volunteer missions hub"
	case RouteServices:
		return "the services menu"
	case RouteMarriage:
		return "opens the Marriage support form directly"
	case RouteMessages:
		return "private chat threads with the support team and other users"
	case RouteSupport:
		return "opens the Support / contact form directly"
	case RouteHome:
		return "the home dashboard"
	default:
		return ""
	}
}

// capabilityText is the prose feature list per role, embedded in the prompt.
func capabilityText(roleID int) string {
	switch roleID {
	case 2: // Eligible
		return `- Submit a project/campaign for admin approval (Kafala → My Projects → Submit New Project).
- View all donations to their campaigns, with grantor names and delivery status (Kafala → My Campaign Donations).
- Start a chat with any grantor who gave to their campaign (tap the chat icon by the grantor's name). The grantor must accept; support is included in every chat.
- Accept or decline incoming chat requests from the Alerts tab or the Messages tab.
- Check pending project requests awaiting admin approval (Kafala → Pending Projects).
- Sell handmade/local products in the marketplace (Services → marketplace listing).
- Edit their profile, browse community resources, and contact the support team.`
	case 3: // Volunteer
		return `- Browse available volunteer missions with description, location, skills and timing (Volunteer tab).
- Sign up / apply for a mission; a coordinator confirms participation (notified in Alerts).
- View their volunteer history and logged hours.
- Update skills and availability in their profile so coordinators can match them.
- Get notified about new missions and urgent assignments in Alerts.
- Browse community guides and the city map; contact the coordination team via Services → Support.`
	default: // Grantor
		return `- Donate to active campaigns (Donate tab → pick a campaign → Donate → enter amount → confirm). Donations are confirmed when received and again when approved by admin.
- View their donation history and per-donation status/details (Donate tab → My Donations).
- Chat with a campaign owner after donating (My Donations → View Details → "Chat with campaign owner"). The owner must accept; support is included.
- Buy handmade/local products from eligibles in the Market tab — every purchase supports the seller.
- Request marriage support and other services (Services tab).
- Sponsor a family through Kafala for ongoing impact.
- Read notifications in Alerts, edit their profile, and explore community resources.`
	}
}

// ──────────────────────────────────────────────────────────────────────────
// Grantor fallback intents
// ──────────────────────────────────────────────────────────────────────────

var donorIntents = []Intent{
	{
		ID:       "d_donate",
		Keywords: []string{"donate", "donation to", "give", "contribut", "fund a", "support a campaign", "how to donate"},
		KeywordsMap: map[string][]string{
			"ar":  {"تبرع", "كيف أتبرع", "حملة", "مساهمة", "تمويل", "منح"},
			"ckb": {"بەخشین", "چۆن بەخشیم", "کامپەین", "مەبەست", "داری بدەم"},
			"kmr": {"بەخشین", "ئەز چەوا ببەخشم", "کامپین", "بەشداری", "پارە"},
		},
		Answer: "To donate, open the Donate tab and browse active campaigns. Tap a campaign to see its goal and progress, then tap \"Donate\", enter your amount, review the summary and confirm. You'll be notified when your donation is received and again once an admin approves it.",
		Answers: map[string]string{
			"ar":  "لتتبرع، افتح تبويب التبرع وتصفح الحملات النشطة. اضغط على أي حملة لرؤية هدفها وتقدمها، ثم اضغط على \"تبرع\"، أدخل المبلغ، راجع الملخص وأكّد. ستتلقى إشعاراً عند استلام تبرعك وآخر عند موافقة المشرف.",
			"ckb": "بۆ بەخشین، تابی بەخشین بکەوە و کامپەینە چالاکەکان ببینە. لەسەر هەر کامپەینێک بپەڕە بۆ دیتنی ئامانج و پێشکەوتنی، ئەوکات \"بەخشین\" بپەڕە، بڕ بنووسە، پوختەکە بپشکنە و پشتگیری بکە. ئاگادارت دەکرێیتەوە کاتێک بەخشینەکەت وەرگیراوە و دیسان کاتێک بەرپرسی پەسەندکردنەکە موافەقەتی دەکات.",
			"kmr": "بۆ بەخشینێ، تابا بەخشینێ ڤەکە و ل کامپینێن چالاک بگەڕە. ل کامپینەکێ کلیک بکە دا ئامانج و پێشکەفتنا وێ ببینی، پاشی \"بەخشین\" کلیک بکە، بڕی پارەی بنڤیسە، کورتییێ ببینە و پشتراست بکە. دێ ئاگەهدار بی دەمێ بەخشینا تە دگەهیتە و دیسا دەمێ بەڕێڤەبەری پەسەند کری.",
		},
		Action: act("Go to Campaigns", RouteDonate),
	},
	{
		ID:       "d_history",
		Keywords: []string{"history", "my donation", "past donation", "previous", "track", "status of my", "receipt", "record"},
		KeywordsMap: map[string][]string{
			"ar":  {"تاريخ التبرعات", "تبرعاتي", "سجل", "تتبع", "حالة التبرع", "السابق"},
			"ckb": {"مێژووی بەخشین", "بەخشینەکانم", "تاریخچەکە", "شوێنکردنەوە"},
			"kmr": {"مێژووا بەخشینان", "بەخشینێن من", "دۆخ", "شوپاندن"},
		},
		Answer: "Your donation history is in the Donate tab — scroll to your personal list. Tap \"View Details\" on any item to see its amount and whether it's been approved, received, or delivered.",
		Answers: map[string]string{
			"ar":  "سجل تبرعاتك موجود في تبويب التبرع — مرر للأسفل للوصول إلى قائمتك الشخصية. اضغط على \"عرض التفاصيل\" لأي بند لرؤية المبلغ وما إذا تمت الموافقة عليه أو استلامه أو تسليمه.",
			"ckb": "مێژووی بەخشینەکانت لە تابی بەخشین دایە — بخلیزە خوارەوە بۆ لیستی کەسیت. لەسەر \"بینینی وردەکاری\" بپەڕە بۆ هەر بابەتێک بۆ دیتنی بڕ و ئەوەی ئایا پەسەند کراوە، وەرگیراوە، یان گەیاندراوە.",
			"kmr": "مێژووا بەخشینێن تە د تابا بەخشینێ دایە — بۆ خوارێ بکێشە بۆ لیستا خۆ. ل \"دیتنا وردەکاری\" بۆ هەر تشتەکێ کلیک بکە دا بڕی و کا هاتیە پەسەندکرن، وەرگرتن یان گەهاندن ببینی.",
		},
		Action: act("View My Donations", RouteMyDonations),
	},
	{
		ID:       "d_chat_owner",
		Keywords: []string{"chat", "contact owner", "message owner", "talk to", "reach the owner", "communicate", "speak with"},
		KeywordsMap: map[string][]string{
			"ar":  {"محادثة", "صاحب الحملة", "تواصل", "رسالة", "كلام", "تحدث"},
			"ckb": {"گفتوگۆ", "خاوەنی کامپەین", "پەیام", "پەیوەندی"},
			"kmr": {"ئاخفتن", "خودانێ کامپینێ", "پەیام", "پەیوەندی"},
		},
		Answer: "After donating to a campaign, open My Donations and tap \"View Details\" on that donation, then \"Chat with campaign owner\" and confirm. The owner is notified and can accept — once accepted, you, the owner, and our support team can message privately.",
		Answers: map[string]string{
			"ar":  "بعد التبرع لحملة، افتح تبرعاتي واضغط على \"عرض التفاصيل\" لذلك التبرع، ثم \"محادثة مع صاحب الحملة\" وأكّد. سيتلقى صاحب الحملة إشعاراً ويمكنه القبول — بمجرد القبول، يمكنكم أنتم وصاحب الحملة وفريق الدعم التراسل بشكل خاص.",
			"ckb": "پاش بەخشین بۆ کامپەینێک، بەخشینەکانم بکەوە و \"بینینی وردەکاری\" بپەڕە لەسەر ئەو بەخشینەکە، ئەوکات \"گفتوگۆ لەگەڵ خاوەنی کامپەین\" بپەڕە و پشتگیری بکە. خاوەنەکە ئاگادار دەکرێیتەوە و دەتوانێت قبووڵ بکات — کاتێک قبووڵ کرا، تۆ، خاوەنەکە و تیمی پشتگیریمان دەتوانن بە تایبەتی پەیامبنێرن.",
			"kmr": "پشتی بەخشینێ، بەخشینێن خۆ ڤەکە و ل \"دیتنا وردەکاری\" بۆ وێ بەخشینێ کلیک بکە، پاشی ل \"ئاخفتن دگەل خودانێ کامپینێ\" کلیک بکە و پشتراست بکە. خودان دێ ئاگەهدار بیت و دشێت پەسەند بکەت — دەمێ پەسەندکر، تو، خودان و تیمێ پشتگیریا مە دشێن ب تایبەتی پەیاما بشینن.",
		},
		Action: act("View My Donations", RouteMyDonations),
	},
	{
		ID:       "d_market",
		Keywords: []string{"market", "buy", "shop", "product", "purchase", "store", "marketplace"},
		KeywordsMap: map[string][]string{
			"ar":  {"سوق", "شراء", "منتج", "تسوق", "طلب", "بازار"},
			"ckb": {"بازاڕ", "کڕین", "بەرهەم", "مەحسووڵ"},
			"kmr": {"بازار", "کڕین", "بەرهەم", "فرۆشگەه"},
		},
		Answer: "Open the Market tab to browse handmade and local products sold by eligibles. Tap a product for photos and price, then place your order — every purchase directly supports the seller's livelihood.",
		Answers: map[string]string{
			"ar":  "افتح تبويب السوق لتصفح المنتجات اليدوية والمحلية التي يبيعها المستحقون. اضغط على أي منتج للاطلاع على الصور والسعر، ثم ضع طلبك — كل عملية شراء تدعم البائع مباشرة.",
			"ckb": "تابی بازاڕ بکەوە بۆ گەڕان لە بەرهەمە دەستکردەکان و شوێنییەکانی فرۆشراو لەلایەن مستحقاکانەوە. لەسەر بەرهەمێک بپەڕە بۆ وێنەکان و نرخ، ئەوکات داواکارییەکەت بنێرە — هەر کڕینێک ڕاستەوخۆ پشتگیری فرۆشەندەکە دەکات.",
			"kmr": "تابا بازارێ ڤەکە دا بەرهەمێن دەستکرن و خۆجهی یێن کو ژ لایێ مستحقان ڤە تێنە فرۆتن ببینی. ل بەرهەمەکێ کلیک بکە بۆ وێنە و بها، پاشی داخوازا خۆ بنێرە — هەر کڕینەک رەستەوخۆ پشتگیریا فرۆشیاری دکەت.",
		},
		Action: act("Open Market", RouteMarket),
	},
	{
		ID:       "d_marriage",
		Keywords: []string{"marriage", "marry", "wedding", "nikah", "zawaj"},
		KeywordsMap: map[string][]string{
			"ar":  {"زواج", "نكاح", "عقد زواج", "دعم زواج", "زواج إسلامي"},
			"ckb": {"زەواج", "خەنابەستن", "پشتگیری زەواج", "نیکاح"},
			"kmr": {"هاوسەرگیری", "نکاح", "پشتگیریا هاوسەرگیریێ"},
		},
		Answer: "Marriage support requests are handled by a dedicated form. Tap below to open it, fill in your details and submit — our team reviews every request and contacts you directly.",
		Answers: map[string]string{
			"ar":  "يتم التعامل مع طلبات دعم الزواج من خلال نموذج مخصص. اضغط أدناه لفتحه، أدخل تفاصيلك وأرسله — فريقنا يراجع كل طلب ويتواصل معك مباشرة.",
			"ckb": "داواکاریە پشتگیری زەواجیەکان لەڕێی فۆرمی تایبەتدا بەڕێوەدەچن. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی، وردەکارییەکانت بنووسە و بینێرە — تیمەکەمان هەموو داواکارییەکی پشکنینەوە دەکات و ڕاستەوخۆ پەیوەندیت پێوە دەکات.",
			"kmr": "داخوازێن پشتگیریا هاوسەرگیریێ ب فۆرمەکا تایبەت تێنە بەڕێڤەبرن. ل خوارێ کلیک بکە دا ڤەکەی، وردەکاریێن خۆ بنڤیسە و بنێرە — تیمێ مە هەر داخوازەکێ ددەتە بەر چاڤان و رەستەوخۆ دگەل تە پەیوەندیێ دکەت.",
		},
		Action: act("Open Marriage Form", RouteMarriage),
	},
	{
		ID:       "d_kafala",
		Keywords: []string{"kafala", "sponsor", "sponsorship", "adopt a family", "ongoing support", "monthly"},
		KeywordsMap: map[string][]string{
			"ar":  {"كفالة", "رعاية", "كفيل", "أسرة", "كفالة أسرة", "راتب شهري"},
			"ckb": {"کەفالە", "پاڵپشتی", "خێزان", "پاڵپشتی مانگانە"},
			"kmr": {"کەفالە", "پشتگیری", "خێزان", "پشتگیریا مانگانە"},
		},
		Answer: "Kafala is our sponsorship programme connecting grantors with families who need ongoing support. You can browse eligible profiles, read their stories and contribute regularly — a lasting impact for a specific family.",
		Answers: map[string]string{
			"ar":  "الكفالة هي برنامج الرعاية لدينا الذي يربط المانحين بالأسر المحتاجة لدعم مستمر. يمكنك تصفح ملفات المستحقين وقراءة قصصهم والمساهمة بانتظام — تأثير دائم لأسرة بعينها.",
			"ckb": "کەفالە بەرنامەی پاڵپشتییمانە کە بەخشەران بە خێزانانی پێویستمەند بە پشتگیری بەردەوام دەبەستێتەوە. دەتوانیت پرۆفایلی مستحقاکان ببینیت، چیرۆکەکانیان بخوێنیتەوە و بە ریتم بەشداری بکەیت — کاریگەرییەکی مەزن بۆ خێزانێکی دیاریکراو.",
			"kmr": "کەفالە بەرنامەیا پشتگیریا مەیە یا کو بەخشەران دگەل خێزانێن پێدڤی ب پشتگیریا بەردەوام گرێ ددەت. تو دشێی پرۆفایلێن مستحقان ببینی، چیرۆکێن وان بخوینی و ب رێکوپێک بەشداری بکەی — کاریگەرییەکا مایندە بۆ خێزانەکا دیاریکری.",
		},
		Action: act("Open Kafala", RouteKafala),
	},
	{
		ID:       "d_notifications",
		Keywords: []string{"notif", "alert", "news", "update", "bell"},
		KeywordsMap: map[string][]string{
			"ar":  {"إشعارات", "تنبيهات", "أخبار", "تحديثات", "الجرس"},
			"ckb": {"ئاگادارکردنەوە", "تنبیه", "هەواڵ", "نوێکردنەوە"},
			"kmr": {"ئاگەهداری", "هشیاری", "نووچە", "نویکرن"},
		},
		Answer: "Tap the Alerts tab to see all your notifications — donation status updates, chat requests, campaign news and more. Swipe any notification to mark it read.",
		Answers: map[string]string{
			"ar":  "اضغط على تبويب التنبيهات لرؤية جميع إشعاراتك — تحديثات حالة التبرع وطلبات المحادثة وأخبار الحملات والمزيد. مرر أي إشعار لتحديد حالته كمقروء.",
			"ckb": "تابی ئاگادارکردنەوەکان بپەڕە بۆ دیتنی هەموو ئاگادارکردنەوەکانت — نوێکردنەوەی حاڵەتی بەخشین، داواکاریە گفتوگۆیەکان، هەواڵی کامپەین و زیاتر. هەر ئاگادارکردنەوەیەک بخلیزە بۆ نیشانەکردنی وەک خوێندراوەوە.",
			"kmr": "تابا ئاگەهداریان کلیک بکە دا هەمی ئاگەهداریێن خۆ ببینی — نویکرنا دۆخێ بەخشینێ، داخوازێن ئاخفتنێ، نووچەیێن کامپینێ و پتر. هەر ئاگەهداریەکێ بخلیزینە دا وەک خواندی نیشان بدەی.",
		},
		Action: act("Go to Alerts", RouteAlerts),
	},
	{
		ID:       "d_profile",
		Keywords: []string{"profile", "edit", "my name", "photo", "picture", "account", "setting"},
		KeywordsMap: map[string][]string{
			"ar":  {"ملف شخصي", "تعديل", "اسم", "صورة", "الحساب", "الإعدادات"},
			"ckb": {"پرۆفایل", "دەستکاریکردن", "ناو", "وێنە", "ژمارەکە"},
			"kmr": {"پرۆفایل", "دەستکاری", "ناڤ", "وێنە", "حساب"},
		},
		Answer: "You can update your name, photo and personal details on the Edit Profile screen. Tap below to open it — changes save immediately.",
		Answers: map[string]string{
			"ar":  "يمكنك تحديث اسمك وصورتك وبياناتك الشخصية في شاشة تعديل الملف الشخصي. اضغط أدناه لفتحها — تُحفظ التغييرات فوراً.",
			"ckb": "دەتوانیت ناوت، وێنەت و وردەکارییە کەسییەکانت لە شاشەی دەستکاریکردنی پرۆفایل نوێ بکەیتەوە. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی — گۆڕانکارییەکان ڕاستەوخۆ پاشکەوت دەکرێن.",
			"kmr": "تو دشێی ناڤێ خۆ، وێنەیێ خۆ و وردەکاریێن کەسی ل سەر سکرینا دەستکاریا پرۆفایلێ نویکەی. ل خوارێ کلیک بکە دا ڤەکەی — گهۆرین رەستەوخۆ تێنە تۆمارکرن.",
		},
		Action: act("Edit Profile", RouteEditProfile),
	},
	{
		ID:       "d_community",
		Keywords: []string{"community", "local", "city", "guide", "resource", "partner", "map"},
		KeywordsMap: map[string][]string{
			"ar":  {"مجتمع", "محلي", "مدينة", "دليل", "موارد"},
			"ckb": {"کۆمەڵگا", "شوێنی", "شار", "ڕێنمایی", "سەرچاوە"},
			"kmr": {"جڤاک", "خۆجهی", "باژێر", "رێبەر", "سەرچاوە"},
		},
		Answer: "The Community section has local service guides, a city map, partner organisations and resources to help you engage with the community around you.",
		Answers: map[string]string{
			"ar":  "يحتوي قسم المجتمع على أدلة الخدمات المحلية وخريطة المدينة والمنظمات الشريكة والموارد التي تساعدك على التفاعل مع مجتمعك.",
			"ckb": "بەشی کۆمەڵگا ڕێنمایییە خزمەتگوزاریە شوێنییەکانی هەیە، نەخشەی شار، ڕێکخراوە هاوبەشەکان و سەرچاوەکان کە یارمەتیت دەدات پەیوەندی لەگەڵ کۆمەڵگاکەی دەوروبەرت بکەیت.",
			"kmr": "بەشا جڤاکی رێبەرێن خزمەتگوزاریێن خۆجهی، نەخشەیا باژێری، رێکخراوێن هەڤکار و سەرچاوەیان هەنە دا هاریکاریا تە بکەن پەیوەندیێ دگەل جڤاکا دەوروبەرا خۆ چێبکەی.",
		},
		Action: act("Open Community", RouteCommunity),
	},
	{
		ID:       "d_services",
		Keywords: []string{"what can", "what else", "feature", "services", "other thing", "help me with", "what do you"},
		KeywordsMap: map[string][]string{
			"ar":  {"خدمات", "ماذا يوجد", "ميزات", "التطبيق", "عروض"},
			"ckb": {"خزمەتگوزاری", "چی هەیە", "تایبەتمەندی", "ئەپ"},
			"kmr": {"خزمەتگوزاری", "چ هەی", "تایبەتمەندی", "ئەپ"},
		},
		Answer: "I can help you donate to campaigns, track your donations, chat with campaign owners, shop the marketplace, sponsor a family through Kafala, request marriage support, and more. What would you like to do?",
		Answers: map[string]string{
			"ar":  "يمكنني مساعدتك في التبرع للحملات، تتبع تبرعاتك، التواصل مع أصحاب الحملات، التسوق في السوق، كفالة أسرة، طلب دعم الزواج، والمزيد. ماذا تريد أن تفعل؟",
			"ckb": "دەتوانم یارمەتیت بدەم لە بەخشین بۆ کامپەینەکان، شوێنکردنەوەی بەخشینەکانت، گفتوگۆ لەگەڵ خاوەنانی کامپەین، کڕین لە بازاڕ، پاڵپشتی خێزان لەڕێی کەفالەوە، داواکاری پشتگیری زەواج، و زیاتر.",
			"kmr": "ئەز دشێم هاریکاریا تە بکەم د بەخشینا کامپینان، شوپاندنا بەخشینێن تە، ئاخفتن دگەل خودانێن کامپینان، کڕین ژ بازارێ، پشتگیریا خێزانێ ب کەفالە، داخوازا پشتگیریا هاوسەرگیریێ، و پتر.",
		},
		Action: act("Explore Services", RouteServices),
	},
}

// ──────────────────────────────────────────────────────────────────────────
// Eligible fallback intents
// ──────────────────────────────────────────────────────────────────────────

var beneficiaryIntents = []Intent{
	{
		ID:       "b_submit",
		Keywords: []string{"submit", "new project", "create campaign", "add project", "apply for", "start a campaign", "post a project"},
		KeywordsMap: map[string][]string{
			"ar":  {"تقديم مشروع", "حملة جديدة", "إضافة مشروع", "طلب تمويل", "نشر مشروع"},
			"ckb": {"تەقدیمکردنی پڕۆژە", "کامپەینی نوێ", "پڕۆژەی نوێ", "داواکاری"},
			"kmr": {"ناردنا پرۆژەی", "کامپینا نوی", "داخوازا پرۆژەی"},
		},
		Answer: "Use the Submit New Project form to add your title, description, goal amount and any supporting documents. Tap below to open it — the admin team reviews it and either approves it or asks for more information.",
		Answers: map[string]string{
			"ar":  "استخدم نموذج تقديم مشروع جديد لإضافة عنوانك ووصفك والمبلغ المستهدف وأي وثائق داعمة. اضغط أدناه لفتحه — يراجعه فريق المشرفين ويوافق عليه أو يطلب مزيداً من المعلومات.",
			"ckb": "فۆرمی تەقدیمکردنی پڕۆژەی نوێ بەکاربهێنە بۆ زیادکردنی ناونیشان، وەسف، بڕی ئامانج و هەر بەڵگەنامەیەکی پشتگیری. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی — تیمی بەڕێوەبەران پشکنینەوەی دەکات و یان پەسەندی دەکات یان زانیاری زیاتر داوا دەکات.",
			"kmr": "فۆرما \"ناردنا پرۆژەیا نوی\" بکار بینە دا ناڤونیشان، پێناسە، بڕی ئامانج و هەر بەلگەیێن پشتگیری زێدە بکەی. ل خوارێ کلیک بکە دا ڤەکەی — تیمێ بەڕێڤەبەری دێ ببینیتە و یان پەسەند دکەت یان زانیاریێن پتر دخوازیت.",
		},
		Action: act("Submit a Project", RouteSubmitProject),
	},
	{
		ID:       "b_donations",
		Keywords: []string{"donation", "received", "my campaign", "how much", "raised", "grantor list", "who donated"},
		KeywordsMap: map[string][]string{
			"ar":  {"تبرعات حملتي", "من تبرع", "مبلغ مجمع", "المانحون", "تبرعات مستلمة"},
			"ckb": {"بەخشینی کامپەینم", "کێ بەخشی", "بڕی کۆکراوەتەوە", "بەخشەران"},
			"kmr": {"بەخشینێن کامپینێن من", "کێ بەخشی", "بەخشەر"},
		},
		Answer: "The My Campaign Donations screen lists all your campaigns and every grantor who contributed, with their amounts and delivery status. Tap below to open it.",
		Answers: map[string]string{
			"ar":  "تعرض شاشة تبرعات حملتي جميع حملاتك وكل مانح ساهم، مع المبالغ وحالة التسليم. اضغط أدناه لفتحها.",
			"ckb": "شاشەی تۆمارکردنی بەخشینی کامپەینەکانم هەموو کامپەینەکانت و هەموو بەخشەرێک کە بەشداری کردووە لیست دەکات، لەگەڵ بڕەکان و حاڵەتی گەیاندن. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.",
			"kmr": "سکرینا \"بەخشینێن کامپینێن من\" هەمی کامپینێن تە و هەر بەخشەرەکێ بەشداربووی، دگەل بڕان و دۆخێ گەهاندنێ لیست دکەت. ل خوارێ کلیک بکە دا ڤەکەی.",
		},
		Action: act("My Campaign Donations", RouteCampaignDonations),
	},
	{
		ID:       "b_chat_donor",
		Keywords: []string{"chat", "grantor", "message", "contact", "talk", "reach grantor"},
		KeywordsMap: map[string][]string{
			"ar":  {"محادثة مانح", "تواصل مع مانح", "رسالة للمانح", "كلام المانح"},
			"ckb": {"گفتوگۆ", "بەخشەر", "پەیام", "پەیوەندی لەگەڵ بەخشەر"},
			"kmr": {"ئاخفتن", "بەخشەر", "پەیام", "پەیوەندی"},
		},
		Answer: "Open My Campaign Donations, find the grantor's row and tap the chat icon next to their name. The grantor is notified and can accept — then you, the grantor and our support team can message privately.",
		Answers: map[string]string{
			"ar":  "افتح تبرعات حملتي، ابحث عن صف المانح واضغط على أيقونة المحادثة بجانب اسمه. سيتلقى المانح إشعاراً ويمكنه القبول — ثم يمكنكم أنتم والمانح وفريق الدعم التراسل بشكل خاص.",
			"ckb": "تۆمارکردنی بەخشینی کامپەینەکانم بکەوە، ڕیزەکەی بەخشەر بدۆزەوە و ئایکۆنی گفتوگۆ لەتەنیشت ناوەکەی بپەڕە. بەخشەرەکە ئاگادار دەکرێیتەوە و دەتوانێت قبووڵ بکات — ئەوکات تۆ، بەخشەرەکە و تیمی پشتگیریمان دەتوانن بە تایبەتی پەیامبنێرن.",
			"kmr": "بەخشینێن کامپینێن خۆ ڤەکە، رێزا بەخشەری بدۆزە و ئایکۆنا ئاخفتنێ ل تەنشتا ناڤێ وی کلیک بکە. بەخشەر دێ ئاگەهدار بیت و دشێت پەسەند بکەت — پاشی تو، بەخشەر و تیمێ پشتگیریا مە دشێن ب تایبەتی پەیاما بشینن.",
		},
		Action: act("My Campaign Donations", RouteCampaignDonations),
	},
	{
		ID:       "b_pending",
		Keywords: []string{"pending", "review", "waiting", "approval", "under review"},
		KeywordsMap: map[string][]string{
			"ar":  {"مشاريع معلقة", "انتظار الموافقة", "قيد المراجعة", "حالة الطلب", "لم يوافق بعد"},
			"ckb": {"هەڵواسراو", "هەڵچاو", "چاوەڕوانی موافەقەت", "حاڵەتی داواکاری"},
			"kmr": {"چاڤەڕوانی", "ل بەندا پەسەندکرنێ", "دۆخێ داخوازێ"},
		},
		Answer: "The Pending Projects screen shows every submission awaiting admin approval. Once approved, it moves to My Projects and becomes visible to grantors. Tap below to open it.",
		Answers: map[string]string{
			"ar":  "تعرض شاشة المشاريع المعلقة كل طلب ينتظر موافقة المشرف. بعد الموافقة، ينتقل إلى مشاريعي ويصبح مرئياً للمانحين. اضغط أدناه لفتحها.",
			"ckb": "شاشەی پڕۆژەکانی هەڵواسراو هەموو تەقدیمێکی چاوەڕواوی موافەقەتی بەڕێوەبەرانی نیشان دەدات. دوای موافەقەت، بۆ پڕۆژەکانم دەگوازرێتەوە و بۆ بەخشەراکان بەچاوەرواندەکرێت. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.",
			"kmr": "سکرینا \"پرۆژەیێن چاڤەڕوانیێ\" هەر ناردنەکا چاڤەڕوانی پەسەندکرنا بەڕێڤەبەری نیشان ددەت. پشتی پەسەندکرنێ، دچیتە \"پرۆژەیێن من\" و بۆ بەخشەران دیار دبیت. ل خوارێ کلیک بکە دا ڤەکەی.",
		},
		Action: act("Pending Projects", RoutePendingProjects),
	},
	{
		ID:       "b_accept_chat",
		Keywords: []string{"accept", "decline", "chat request", "incoming", "someone wants"},
		KeywordsMap: map[string][]string{
			"ar":  {"قبول محادثة", "رفض محادثة", "طلب محادثة", "موافقة على محادثة"},
			"ckb": {"قبووڵکردن", "ڕەتکردنەوە", "داواکاریی گفتوگۆ", "موافەقەت"},
			"kmr": {"پەسەندکرن", "ڕەتکرن", "داخوازا ئاخفتنێ"},
		},
		Answer: "When a grantor requests a chat you'll get a notification in Alerts with Accept and Decline buttons right inside it. You can also accept or decline from the top of the Messages tab.",
		Answers: map[string]string{
			"ar":  "عندما يطلب مانح محادثة، ستتلقى إشعاراً في التنبيهات بزري القبول والرفض مباشرة فيه. يمكنك أيضاً القبول أو الرفض من أعلى تبويب الرسائل.",
			"ckb": "کاتێک بەخشەرێک گفتوگۆ داوا دەکات، ئاگادارکردنەوەیەکت لە تابی ئاگادارکردنەوەکان دەگات لەگەڵ تەکمەکانی قبووڵکردن و ڕەتکردنەوە ڕاستەوخۆ تیایدا. دەتوانیت هەروەها قبووڵ بکەیت یان ڕەتی بکەیتەوە لە سەرەوەی تابی پەیامەکان.",
			"kmr": "دەمێ بەخشەرەک داخوازا ئاخفتنێ دکەت، دێ ئاگەهداریەک د تابا ئاگەهداریان دا دگەل دوگمەیێن پەسەندکرن و ڕەتکرنێ رەستەوخۆ تێدا بگری. تو دشێی هەروەسا ژ سەرێ تابا پەیامان پەسەند یان ڕەت بکەی.",
		},
		Action: act("Go to Alerts", RouteAlerts),
	},
	{
		ID:       "b_market",
		Keywords: []string{"sell", "market", "product", "list", "income", "marketplace", "my goods"},
		KeywordsMap: map[string][]string{
			"ar":  {"بيع", "سوق", "منتجات", "دخل", "قائمة منتج", "بيع منتجات"},
			"ckb": {"فرۆشتن", "بازاڕ", "بەرهەم", "داهات"},
			"kmr": {"فرۆتن", "بازار", "بەرهەم", "داهات"},
		},
		Answer: "Go to Services to add a marketplace listing — upload photos, a price and a description. Once approved, grantors browsing the Market can buy it, giving you a direct source of income.",
		Answers: map[string]string{
			"ar":  "اذهب إلى الخدمات لإضافة قائمة في السوق — ارفع صوراً وسعراً ووصفاً. بعد الموافقة، يمكن للمانحين المتصفحين في السوق شراؤه، مما يوفر لك مصدر دخل مباشر.",
			"ckb": "بچۆ بۆ خزمەتگوزارییەکان بۆ زیادکردنی لیستە بازاڕییەکە — وێنە، نرخ و وەسف بکەوتەوە. دوای موافەقەت، بەخشەرانی گەڕانی بازاڕ دەتوانن بیکڕن، کە سەرچاوەیەکی داهاتی ڕاستەوخۆت پێ دەبەخشێت.",
			"kmr": "بچۆ خزمەتگوزاریان دا لیستەیەکا بازارێ زێدە بکەی — وێنە، بها و پێناسە. پشتی پەسەندکرنێ، بەخشەرێن د بازارێ دا دگەڕن دشێن بکڕن، کو سەرچاوەیەکا داهاتی رەستەوخۆ ددەتە تە.",
		},
		Action: act("Open Services", RouteServices),
	},
	{
		ID:       "b_profile",
		Keywords: []string{"profile", "edit", "my name", "photo", "account", "setting"},
		KeywordsMap: map[string][]string{
			"ar":  {"ملف شخصي", "تعديل", "بياناتي", "صورة", "معلوماتي"},
			"ckb": {"پرۆفایل", "دەستکاریکردن", "زانیاریم", "وێنە"},
			"kmr": {"پرۆفایل", "دەستکاری", "زانیاریێن من"},
		},
		Answer: "Keep your contact details and photo current on the Edit Profile screen — grantors and the support team see your profile when reviewing your campaigns. Tap below to open it.",
		Answers: map[string]string{
			"ar":  "احتفظ ببيانات الاتصال وصورتك محدّثة في شاشة تعديل الملف الشخصي — يرى المانحون وفريق الدعم ملفك الشخصي عند مراجعة حملاتك. اضغط أدناه لفتحها.",
			"ckb": "وردەکاریی پەیوەندی و وێنەکەت کاتبەکات لە شاشەی دەستکاریکردنی پرۆفایل — بەخشەران و تیمی پشتگیری پرۆفایلەکەت دەبینن کاتێک کامپەینەکانت پشکنینەوە دەکەن. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.",
			"kmr": "وردەکاریێن پەیوەندیێ و وێنەیێ خۆ ل سەر سکرینا دەستکاریا پرۆفایلێ رۆژانە بهێلە — بەخشەر و تیمێ پشتگیری پرۆفایلا تە دەمێ کامپینێن تە ددەنە بەر چاڤان دبینن. ل خوارێ کلیک بکە دا ڤەکەی.",
		},
		Action: act("Edit Profile", RouteEditProfile),
	},
	{
		ID:       "b_community",
		Keywords: []string{"community", "resource", "local", "city", "service near", "help near"},
		KeywordsMap: map[string][]string{
			"ar":  {"مجتمع", "موارد", "خدمات محلية", "المنطقة"},
			"ckb": {"کۆمەڵگا", "سەرچاوە", "خزمەتگوزارییە شوێنییەکان"},
			"kmr": {"جڤاک", "سەرچاوە", "خزمەتگوزاریێن خۆجهی"},
		},
		Answer: "The Community section has local service guides, partner organisations and city-level resources to help you access support in your area.",
		Answers: map[string]string{
			"ar":  "يحتوي قسم المجتمع على أدلة الخدمات المحلية والمنظمات الشريكة والموارد على مستوى المدينة لمساعدتك على الوصول إلى الدعم في منطقتك.",
			"ckb": "بەشی کۆمەڵگا ڕێنماییی خزمەتگوزاریی شوێنی، ڕێکخراوە هاوبەشەکان و سەرچاوەکانی ئاستی شار هەیە بۆ یارمەتیدانت لە دەستگەیشتن بۆ پشتگیری لە ناوچەکەت.",
			"kmr": "بەشا جڤاکی رێبەرێن خزمەتگوزاریێن خۆجهی، رێکخراوێن هەڤکار و سەرچاوەیێن ل ئاستێ باژێری هەنە دا هاریکاریا تە بکەن د گەهشتنا پشتگیریێ ل دەڤەرا خۆ.",
		},
		Action: act("Open Community", RouteCommunity),
	},
	{
		ID:       "b_support",
		Keywords: []string{"support", "help", "contact team", "admin", "problem", "issue", "ticket"},
		KeywordsMap: map[string][]string{
			"ar":  {"دعم", "مساعدة", "فريق الدعم", "مشكلة", "تذكرة", "تواصل مع الفريق"},
			"ckb": {"پشتگیری", "یارمەتی", "تیمی پشتگیری", "کێشە", "پرۆبلیم"},
			"kmr": {"پشتگیری", "هاریکاری", "تیمێ پشتگیری", "کێشە"},
		},
		Answer: "Use the Support form to message our team — we aim to respond within 24 hours. For urgent matters you can reply directly to any notification from us. Tap below to open it.",
		Answers: map[string]string{
			"ar":  "استخدم نموذج الدعم لمراسلة فريقنا — نهدف إلى الرد خلال 24 ساعة. للأمور العاجلة، يمكنك الرد مباشرة على أي إشعار منا. اضغط أدناه لفتحه.",
			"ckb": "فۆرمی پشتگیری بەکاربهێنە بۆ ئەوەی نامەی تیمەکەمان بنێریت — ئامانجمان وەڵامدانەوە لە ماوەی ٢٤ کاتژمێردایە. بۆ کارەکانی ئازگیر دەتوانیت ڕاستەوخۆ وەڵامی هەر ئاگادارکردنەوەیەک بدەیتەوە. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.",
			"kmr": "فۆرما پشتگیریێ بکار بینە دا پەیاما بۆ تیمێ مە بشینی — ئامانجا مە ئەوە کو د ناڤ ٢٤ دەمژمێران دا بەرسڤ بدەین. بۆ کارێن لەزگین تو دشێی رەستەوخۆ بەرسڤا هەر ئاگەهداریەکێ ژ مە بدەی. ل خوارێ کلیک بکە دا ڤەکەی.",
		},
		Action: act("Contact Support", RouteSupport),
	},
	{
		ID:       "b_messages",
		Keywords: []string{"messages", "accepted", "conversation", "thread", "inbox", "open chat"},
		KeywordsMap: map[string][]string{
			"ar":  {"رسائل", "محادثات", "صندوق الوارد", "الرسائل المقبولة", "محادثاتي"},
			"ckb": {"پەیامەکان", "گفتوگۆکان", "باسکردنەکان", "ئینبۆکس"},
			"kmr": {"پەیام", "ئاخفتن", "ئینبۆکس", "گفتوگۆ"},
		},
		Answer: "Once a chat request is accepted by either side, the conversation appears in the Messages tab. Our support team is included in every chat for your safety.",
		Answers: map[string]string{
			"ar":  "بمجرد قبول طلب محادثة من أي طرف، تظهر المحادثة في تبويب الرسائل. فريق الدعم لدينا متضمن في كل محادثة لسلامتك.",
			"ckb": "کاتێک داواکارییەکی گفتوگۆ لەلایەن هەر لاوێک قبووڵ کرا، گفتوگۆکە لە تابی پەیامەکان دەردەکەوێت. تیمی پشتگیریمان لە هەموو گفتوگۆیەک بۆ ئاسایشت تێ دایە.",
			"kmr": "دەمێ داخوازا ئاخفتنێ ژ لایێ هەر دوو لایان ڤە هاتە پەسەندکرن، ئاخفتن د تابا پەیامان دا دیار دبیت. تیمێ پشتگیریا مە د هەر ئاخفتنەکێ دا بۆ سەلامەتیا تە هەیە.",
		},
		Action: act("Open Messages", RouteMessages),
	},
}

// ──────────────────────────────────────────────────────────────────────────
// Volunteer fallback intents
// ──────────────────────────────────────────────────────────────────────────

var volunteerIntents = []Intent{
	{
		ID:       "v_missions",
		Keywords: []string{"mission", "task", "available", "see mission", "what work", "opportunit"},
		KeywordsMap: map[string][]string{
			"ar":  {"مهمة", "عمل تطوعي", "فرص تطوع", "مهام متاحة", "ماذا أفعل"},
			"ckb": {"ئەرک", "کاری ڕاهێنانی", "دەرفەتە ڕاهێنانییەکان"},
			"kmr": {"ئەرک", "خۆبەخشی", "دەرفەت"},
		},
		Answer: "Open the Volunteer tab to see all active missions with their task description, location, required skills and timing. Tap any mission to read the full details.",
		Answers: map[string]string{
			"ar":  "افتح تبويب التطوع لرؤية جميع المهام النشطة مع وصف المهمة والموقع والمهارات المطلوبة والتوقيت. اضغط على أي مهمة لقراءة التفاصيل الكاملة.",
			"ckb": "تابی ڕاهێنان بکەوە بۆ دیتنی هەموو ئەرکە چالاکەکان لەگەڵ وەسفی ئەرک، شوێن، مەهارەتی پێویست و کات. لەسەر هەر ئەرکێک بپەڕە بۆ خوێندنەوەی وردەکاری تەواو.",
			"kmr": "تابا خۆبەخشیێ ڤەکە دا هەمی ئەرکێن چالاک دگەل پێناسەیا ئەرکی، جه، شیانێن پێدڤی و دەمی ببینی. ل هەر ئەرکەکێ کلیک بکە دا وردەکاریێن تەمام بخوینی.",
		},
		Action: act("Open Volunteer", RouteVolunteer),
	},
	{
		ID:       "v_signup",
		Keywords: []string{"sign up", "join", "apply", "register for", "participate", "enroll", "how to join"},
		KeywordsMap: map[string][]string{
			"ar":  {"تسجيل تطوع", "انضمام", "تقديم طلب تطوع", "مشاركة"},
			"ckb": {"تۆمارکردن", "بەشدار", "تەقدیم", "چۆن تۆمار بکەم"},
			"kmr": {"تۆمارکرن", "بەشداری", "داخواز", "چەوا بەشداری بکەم"},
		},
		Answer: "In the Volunteer tab, tap the mission you want and then \"Apply\". The coordinator reviews your application and confirms — you'll be notified in Alerts.",
		Answers: map[string]string{
			"ar":  "في تبويب التطوع، اضغط على المهمة التي تريدها ثم \"تقدم\". يراجع المنسق طلبك ويؤكد — ستتلقى إشعاراً في التنبيهات.",
			"ckb": "لە تابی ڕاهێنان، لەسەر ئەرکی دەویت بپەڕە ئەوکات \"تەقدیم بکە\". هەماهەنگکەرەکە تەقدیمەکەت پشکنینەوە دەکات و پشتگیری دەکات — لە تابی ئاگادارکردنەوەکان ئاگادارت دەکرێتەوە.",
			"kmr": "د تابا خۆبەخشیێ دا، ل ئەرکێ کو دخوازی کلیک بکە و پاشی \"داخواز بکە\". هەماهەنگکار داخوازا تە ددەتە بەر چاڤان و پشتراست دکەت — دێ د ئاگەهداریان دا ئاگەهدار بی.",
		},
		Action: act("Open Volunteer", RouteVolunteer),
	},
	{
		ID:       "v_history",
		Keywords: []string{"history", "completed", "my mission", "hours", "past", "record"},
		KeywordsMap: map[string][]string{
			"ar":  {"سجل التطوع", "مهام مكتملة", "ساعات التطوع", "تاريخ"},
			"ckb": {"مێژووی ڕاهێنان", "ئەرکی تەواوبووم", "کاتژمێرەکانم"},
			"kmr": {"مێژووا خۆبەخشیێ", "ئەرکێن تەمامکری", "دەمژمێرێن من"},
		},
		Answer: "Your completed missions and logged hours are recorded in the Volunteer section — scroll to the history list to review all your contributions.",
		Answers: map[string]string{
			"ar":  "مهامك المكتملة وساعاتك المسجلة مسجلة في قسم التطوع — مرر للأسفل إلى قائمة السجل لمراجعة جميع مساهماتك.",
			"ckb": "ئەرکە تەواوبووەکانت و کاتژمێرە تۆمارکراوەکانت لە بەشی ڕاهێناندا تۆماردراون — بخلیزە خوارەوە بۆ لیستی مێژوو بۆ پشکنینەوەی هەموو بەشداریکردنەکانت.",
			"kmr": "ئەرکێن تە یێن تەمامکری و دەمژمێرێن تۆمارکری د بەشا خۆبەخشیێ دا تێنە تۆمارکرن — بۆ خوارێ بخلیزینە بۆ لیستا مێژوویێ دا هەمی بەشداریێن خۆ ببینی.",
		},
		Action: act("Open Volunteer", RouteVolunteer),
	},
	{
		ID:       "v_skills",
		Keywords: []string{"skill", "availability", "experience", "certif", "schedule", "update my"},
		KeywordsMap: map[string][]string{
			"ar":  {"مهارات", "توافر", "جدول زمني", "تحديث مهاراتي"},
			"ckb": {"مەهارەت", "بەردەستبوون", "خشتە", "نوێکردنەوەی مەهارەت"},
			"kmr": {"شیان", "بەردەستبوون", "خشتەیا من"},
		},
		Answer: "Your skills and schedule live in your profile. Open the Edit Profile screen to update your skills, availability and any certifications so coordinators can match you to the right missions.",
		Answers: map[string]string{
			"ar":  "مهاراتك وجدولك موجودان في ملفك الشخصي. افتح شاشة تعديل الملف الشخصي لتحديث مهاراتك وتوافرك وأي شهادات حتى يتمكن المنسقون من مطابقتك مع المهام المناسبة.",
			"ckb": "مەهارەت و خشتەکانت لە پرۆفایلەکەتدا دەژین. شاشەی دەستکاریکردنی پرۆفایل بکەوە بۆ نوێکردنەوەی مەهارەت، بەردەستبوون و هەر تایبەتمەندیەک تا هەماهەنگکەران بتوانن بیانتەبقینن لەگەڵ ئەرکەکانی گونجاو.",
			"kmr": "شیان و خشتەیا تە د پرۆفایلا تە دا نە. سکرینا دەستکاریا پرۆفایلێ ڤەکە دا شیان، بەردەستبوون و هەر بڕوانامەیان نویکەی دا هەماهەنگکار بشێن تە دگەل ئەرکێن گونجای رێک بخن.",
		},
		Action: act("Edit Profile", RouteEditProfile),
	},
	{
		ID:       "v_notifications",
		Keywords: []string{"notif", "alert", "new mission", "remind", "inform"},
		KeywordsMap: map[string][]string{
			"ar":  {"إشعارات", "تنبيهات", "مهام جديدة", "تحديثات"},
			"ckb": {"ئاگادارکردنەوە", "تنبیه", "ئەرکی نوێ", "نوێکردنەوە"},
			"kmr": {"ئاگەهداری", "هشیاری", "ئەرکێن نوی"},
		},
		Answer: "Notifications about new missions, urgent assignments and status updates appear in the Alerts tab. Keep phone notifications enabled so you don't miss time-sensitive tasks.",
		Answers: map[string]string{
			"ar":  "تظهر إشعارات المهام الجديدة والمهام العاجلة وتحديثات الحالة في تبويب التنبيهات. أبق إشعارات الهاتف مفعّلة حتى لا تفوتك المهام الحساسة للوقت.",
			"ckb": "ئاگادارکردنەوەکانی بارەی ئەرکی نوێ، ئەرکی ئازگیر و نوێکردنەوەی حاڵەت لە تابی ئاگادارکردنەوەکان دەردەکەون. ئاگادارکردنەوەکانی تەلەفۆن چالاک بهێڵەوە تا ئەرکە کاتژمێرییەکان لەدەستت نەچن.",
			"kmr": "ئاگەهداریێن دەربارەی ئەرکێن نوی، ئەرکێن لەزگین و نویکرنا دۆخی د تابا ئاگەهداریان دا دیار دبن. ئاگەهداریێن مۆبایلی چالاک بهێلە دا ئەرکێن دەمدار ژ دەست نەدەی.",
		},
		Action: act("Go to Alerts", RouteAlerts),
	},
	{
		ID:       "v_community",
		Keywords: []string{"community", "local", "city", "map", "resource", "area"},
		KeywordsMap: map[string][]string{
			"ar":  {"مجتمع", "خريطة", "دليل", "موارد محلية"},
			"ckb": {"کۆمەڵگا", "شوێنی", "شار", "نەخشە", "سەرچاوە"},
			"kmr": {"جڤاک", "خۆجهی", "باژێر", "نەخشە"},
		},
		Answer: "The Community section has local service guides, partner info and the city map — useful for field work and understanding the areas you'll be working in.",
		Answers: map[string]string{
			"ar":  "يحتوي قسم المجتمع على أدلة الخدمات المحلية ومعلومات الشركاء وخريطة المدينة — مفيدة للعمل الميداني وفهم المناطق التي ستعمل فيها.",
			"ckb": "بەشی کۆمەڵگا ڕێنمایییە خزمەتگوزاریی شوێنییەکانی هەیە، زانیاری هاوبەش و نەخشەی شار — سوودمەندن بۆ کاری مەیدانی و تێگەیشتن لە ناوچەکانی کارکردن.",
			"kmr": "بەشا جڤاکی رێبەرێن خزمەتگوزاریێن خۆجهی، زانیاریێن هەڤکاران و نەخشەیا باژێری هەنە — بۆ کارێ مەیدانی و تێگەهشتنا دەڤەرێن کو تو تێدا کار دکەی سوودمەند.",
		},
		Action: act("Open Community", RouteCommunity),
	},
	{
		ID:       "v_support",
		Keywords: []string{"contact", "coordinator", "support", "help", "team", "problem", "issue"},
		KeywordsMap: map[string][]string{
			"ar":  {"دعم", "منسق", "مساعدة", "مشكلة ميدانية", "فريق التنسيق"},
			"ckb": {"پشتگیری", "هەماهەنگکەر", "یارمەتی", "کێشەی مەیدانی"},
			"kmr": {"پشتگیری", "هەماهەنگکار", "هاریکاری", "کێشە"},
		},
		Answer: "Use the Support form to message our coordination team. For urgent field issues, reply directly to any mission notification in your Alerts tab. Tap below to open it.",
		Answers: map[string]string{
			"ar":  "استخدم نموذج الدعم لمراسلة فريق التنسيق لدينا. للمشكلات الميدانية العاجلة، رد مباشرة على أي إشعار مهمة في تبويب التنبيهات. اضغط أدناه لفتحه.",
			"ckb": "فۆرمی پشتگیری بەکاربهێنە بۆ ئەوەی نامەی تیمی هەماهەنگکردنەکەمان بنێریت. بۆ کارەکانی مەیدانی ئازگیر، ڕاستەوخۆ وەڵامی هەر ئاگادارکردنەوەیەکی ئەرک بدەرەوە لە تابی ئاگادارکردنەوەکانت. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.",
			"kmr": "فۆرما پشتگیریێ بکار بینە دا پەیاما بۆ تیمێ هەماهەنگیا مە بشینی. بۆ کێشەیێن مەیدانی یێن لەزگین، رەستەوخۆ بەرسڤا هەر ئاگەهداریا ئەرکێ د تابا ئاگەهداریان دا بدە. ل خوارێ کلیک بکە دا ڤەکەی.",
		},
		Action: act("Contact Support", RouteSupport),
	},
	{
		ID:       "v_profile",
		Keywords: []string{"profile", "edit", "my name", "photo", "account", "setting"},
		KeywordsMap: map[string][]string{
			"ar":  {"ملف شخصي", "تعديل", "بياناتي", "معلوماتي"},
			"ckb": {"پرۆفایل", "دەستکاریکردن", "زانیاریم"},
			"kmr": {"پرۆفایل", "دەستکاری", "زانیاریێن من"},
		},
		Answer: "Keep your contact details and availability up to date on the Edit Profile screen so coordinators can reach you. Tap below to open it.",
		Answers: map[string]string{
			"ar":  "احتفظ ببيانات الاتصال وتوافرك محدّثة في شاشة تعديل الملف الشخصي حتى يتمكن المنسقون من التواصل معك. اضغط أدناه لفتحها.",
			"ckb": "وردەکاریی پەیوەندی و بەردەستبوونت کاتبەکات لە شاشەی دەستکاریکردنی پرۆفایل تا هەماهەنگکەران بتوانن پەیوەندیت پێوە بکەن. تەکمەی خوارەوە بپەڕە بۆ کردنەوەی.",
			"kmr": "وردەکاریێن پەیوەندیێ و بەردەستبوونا خۆ ل سەر سکرینا دەستکاریا پرۆفایلێ رۆژانە بهێلە دا هەماهەنگکار بشێن پەیوەندیێ دگەل تە بکەن. ل خوارێ کلیک بکە دا ڤەکەی.",
		},
		Action: act("Edit Profile", RouteEditProfile),
	},
}

// ──────────────────────────────────────────────────────────────────────────
// About-the-app intents — shared across every role (appended in intentsFor).
// ──────────────────────────────────────────────────────────────────────────

var aboutAppIntents = []Intent{
	{
		ID:       "about_app",
		Keywords: []string{"about", "what is this app", "what app", "platform", "purpose", "what does this app"},
		KeywordsMap: map[string][]string{
			"ar":  {"ما هو التطبيق", "عن التطبيق", "ما هذا", "المنصة"},
			"ckb": {"دەربارەی ئەپ", "ئەپ چییە", "ئەمە چییە", "سەکۆ"},
			"kmr": {"دەربارەی ئەپی", "ئەپ چییە", "ئەڤ چییە", "پلاتفۆرم"},
		},
		Answer: "This is a humanitarian aid platform that connects grantors, eligibles and volunteers. You can donate to campaigns, sponsor families through Kafala, request or receive aid, buy and sell in the eligible marketplace, join volunteer missions, and reach community services — all in one place.",
		Answers: map[string]string{
			"ar":  "هذه منصة إغاثة إنسانية تربط المانحين والمستحقين والمتطوعين. يمكنك التبرع للحملات، كفالة أسر عبر الكفالة، طلب أو تلقي المساعدة، البيع والشراء في سوق المستحقين، الانضمام لمهام التطوع، والوصول إلى خدمات المجتمع — كل ذلك في مكان واحد.",
			"ckb": "ئەمە سەکۆیەکی یارمەتی مرۆییە کە بەخشەر، مستحق و خۆبەخشان بەیەکەوە دەبەستێتەوە. دەتوانیت بەخشین بۆ کامپەینەکان بکەیت، خێزان لەڕێی کەفالەوە پاڵپشتی بکەیت، داوای یارمەتی بکەیت یان وەریبگریت، لە بازاڕی مستحقاندا بکڕیت و بفرۆشیت، بەشداری ئەرکی خۆبەخشی بکەیت، و دەستت بگات بە خزمەتگوزاریی کۆمەڵگا — هەمووی لە یەک شوێندا.",
			"kmr": "ئەڤ پلاتفۆرمەکا یارمەتیا مرۆڤایەتییە یا کو بەخشەر، مستحق و خۆبەخشان بەیەکڤە گرێ ددەت. تو دشێی بۆ کامپینان ببەخشی، خێزانان ب کەفالە پاڵپشتی بکەی، داخوازا یارمەتیێ بکەی یان وەربگری، ل بازارا مستحقان بکڕی و بفرۆشی، بەشداری ئەرکێن خۆبەخشیێ بکەی، و گەهشتنا خزمەتگوزاریێن جڤاکی بکەی — هەمی ل یەک جهی.",
		},
		Action: act("Explore Services", RouteServices),
	},
	{
		ID:       "about_how",
		Keywords: []string{"how it works", "how does", "how to use", "navigate", "guide me"},
		KeywordsMap: map[string][]string{
			"ar":  {"كيف يعمل", "طريقة العمل", "كيف أستخدم"},
			"ckb": {"چۆن کار دەکات", "چۆن بەکاربهێنم", "ڕێنمایی"},
			"kmr": {"چەوا کار دکەت", "چەوا بکاربینم", "رێبەری"},
		},
		Answer: "Pick what you need from the tabs: Home shows highlights and quick actions; Donate and Kafala for giving and sponsorships; Market for products; Services for forms like marriage support and eligible cases; Alerts for updates; and Messages to chat. The admin team reviews requests and you are notified at every step.",
		Answers: map[string]string{
			"ar":  "اختر ما تحتاجه من التبويبات: الرئيسية تعرض أهم الأمور والإجراءات السريعة؛ التبرع والكفالة للعطاء والكفالات؛ السوق للمنتجات؛ الخدمات للنماذج مثل دعم الزواج وحالات المستحقين؛ التنبيهات للتحديثات؛ والرسائل للمحادثة. يراجع فريق الإدارة الطلبات وتصلك إشعارات في كل خطوة.",
			"ckb": "ئەوەی پێویستتە لە تابەکان هەڵبژێرە: سەرەتا گرنگترین شتەکان و کردارە خێراکان پیشان دەدات؛ بەخشین و کەفالە بۆ بەخشین و کەفالەکان؛ بازاڕ بۆ بەرهەمەکان؛ خزمەتگوزارییەکان بۆ فۆرمەکان وەک پشتگیری زەواج و کەیسی مستحقان؛ ئاگادارکردنەوەکان بۆ نوێکارییەکان؛ و پەیامەکان بۆ گفتوگۆ. تیمی بەڕێوەبردن داواکارییەکان پشکنینەوە دەکات و لە هەر هەنگاوێکدا ئاگادار دەکرێیتەوە.",
			"kmr": "ئەوا پێدڤیی تە یە ژ تابان هەلبژێرە: سەرەکی گرنگترین تشتان و کارێن لەز نیشان ددەت؛ بەخشین و کەفالە بۆ بەخشین و کەفالان؛ بازار بۆ بەرهەمان؛ خزمەتگوزاری بۆ فۆرمان وەک پشتگیریا زەواجێ و کەیسێن مستحقان؛ ئاگەهداری بۆ نویکاریان؛ و پەیام بۆ ئاخفتنێ. تیمێ بەڕێڤەبرینێ داخوازان ددەتە بەر چاڤان و تو د هەر گاڤەکێ دا ئاگەهدار دبی.",
		},
		Action: act("Explore Services", RouteServices),
	},
	{
		ID:       "about_start",
		Keywords: []string{"get started", "getting started", "begin", "new here", "first time", "start"},
		KeywordsMap: map[string][]string{
			"ar":  {"كيف أبدأ", "البداية", "أنا جديد"},
			"ckb": {"چۆن دەست پێ بکەم", "دەستپێک", "نوێم"},
			"kmr": {"چەوا دەست پێ بکەم", "دەستپێک", "ئەز نوی مە"},
		},
		Answer: "Start by completing your profile so your account looks trusted. Then explore the tabs that match your role — donate or sponsor, submit a request, or join a mission. Tap any suggested question here and I will take you straight to the right screen.",
		Answers: map[string]string{
			"ar":  "ابدأ بإكمال ملفك الشخصي ليبدو حسابك موثوقاً. ثم استكشف التبويبات المناسبة لدورك — تبرّع أو اكفل، قدّم طلباً، أو انضم لمهمة. اضغط أي سؤال مقترح هنا وسآخذك مباشرة إلى الشاشة الصحيحة.",
			"ckb": "بە تەواوکردنی پرۆفایلەکەت دەست پێ بکە تا هەژمارەکەت متمانەپێکراو دیار بێت. ئینجا ئەو تابانە بگەڕێ کە لەگەڵ ڕۆڵەکەتدا دەگونجێن — بەخشین بکە یان کەفالە، داواکارییەک پێشکەش بکە، یان بەشداری ئەرکێک بکە. هەر پرسیارێکی پێشنیارکراو لێرە بپەڕە و ڕاستەوخۆ دەتبەمە شاشە دروستەکە.",
			"kmr": "ب تەمامکرنا پرۆفایلا خۆ دەست پێ بکە دا حسابێ تە باوەرپێکری دیار بیت. پاشی وان تابان بگەڕە یێن کو دگەل ڕۆلا تە دگونجن — ببەخشە یان کەفالە بکە، داخوازەکێ پێشکێش بکە، یان بەشداری ئەرکەکێ بکە. هەر پرسیارەکا پێشنیارکری ل ڤێرە بتکینە و ئەز دێ رەستەوخۆ تە بەمە شاشا دروست.",
		},
		Action: act("Edit Profile", RouteEditProfile),
	},
}
