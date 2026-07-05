// templates.go — every user-facing notification copy, in all 4 supported
// languages. One builder function per trigger; each returns a ready-to-Send
// LocalizedMessage.
//
// Phase 18 — full restoration of the PHP notification catalogue. The PHP
// source-of-truth file (`.archive/percentage/database/notification_texts.php`)
// is missing from the archive, so Sorani + Badini translations here are
// fresh first-pass drafts that should be reviewed by a native speaker
// before launch.
//
// Locale legend:
//
//	En  — English
//	Ar  — Arabic (Modern Standard)
//	Ckb — Kurdish Sorani  (Central Kurdish, Arabic script)
//	Kmr — Kurdish Badini  (Northern Kurdish, Arabic script as used in Iraq)
//
// Conventions:
//   - All strings use "{placeholder}" with %s — we sprintf at build time.
//   - The notification_type values match what the PHP code wrote, so the
//     mobile app's existing per-type rendering keeps working.
//   - related_entity_type is the table name; related_entity_id is its PK.

package notify

import (
	"fmt"
	"strings"
)

// ============================================================================
// SUBMIT-TIME TEMPLATES — replaces the inline EN+AR strings that lived in
// extras.go, beneficiary.go, marketplace.go. Each is now 4-language.
// ============================================================================

// DonationSubmittedMsg — donor just submitted a donation. The PHP API
// never sent one; this is a new-in-Go acknowledgement so donors get
// instant confirmation in their notifications list (rather than only seeing
// something happen when admin approves, which can be hours later).
func DonationSubmittedMsg(amount, currency, campaignName string, donationID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "donation_submitted",
		RelatedEntityType: "donations",
		RelatedEntityID:   donationID,
		Title: LocalText{
			En:  "Donation received",
			Ar:  "تم استلام التبرع",
			Ckb: "بەخشینەکە وەرگیرا",
			Kmr: "بەخشین هاتە وەرگرتن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your %s %s donation to \"%s\" was received and is being reviewed. We'll notify you when it's approved.", amount, currency, campaignName),
			Ar:  fmt.Sprintf("تم استلام تبرعك بمبلغ %s %s للحملة \"%s\" وهو قيد المراجعة. سنبلغك عندما تتم الموافقة عليه.", amount, currency, campaignName),
			Ckb: fmt.Sprintf("بەخشینەکەت بە بڕی %s %s بۆ «%s» وەرگیرا و لە پێداچوونەوەدایە. کاتێک پەسەند کرا ئاگادارت دەکەینەوە.", amount, currency, campaignName),
			Kmr: fmt.Sprintf("بەخشینا تە یا %s %s بۆ «%s» هاتە وەرگرتن و د پشکنینێ دایە. دەمێ هاتە قبوولکرن، تە ئاگەهدار دکەین.", amount, currency, campaignName),
		},
	}
}

// SponsorshipSubmittedMsg — donor just created a sponsorship.
func SponsorshipSubmittedMsg(amount, currency, projectName string, sponsorshipID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "sponsorship_submitted",
		RelatedEntityType: "sponsorships",
		RelatedEntityID:   sponsorshipID,
		Title: LocalText{
			En:  "Sponsorship request submitted",
			Ar:  "تم إرسال طلب الكفالة",
			Ckb: "داواکاری سپۆنسەرکردن نێردرا",
			Kmr: "داخوازا سپۆنسەری هاتە شاندن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your %s %s monthly sponsorship for %s was sent for admin review.", amount, currency, projectName),
			Ar:  fmt.Sprintf("تم إرسال كفالتك الشهرية بمبلغ %s %s للمشروع \"%s\" إلى المسؤول للمراجعة.", amount, currency, projectName),
			Ckb: fmt.Sprintf("سپۆنسەری مانگانەی تۆ بە بڕی %s %s بۆ «%s» بۆ پێداچوونەوەی بەڕێوەبەر نێردرا.", amount, currency, projectName),
			Kmr: fmt.Sprintf("سپۆنسەریا تە یا مەهانە یا %s %s بۆ «%s» بۆ پشکنینا بەرپرسی هاتە شاندن.", amount, currency, projectName),
		},
	}
}

// SponsorshipCancelledByDonorMsg — donor cancelled their own active sponsorship.
func SponsorshipCancelledByDonorMsg(projectName string, sponsorshipID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "sponsorship_cancelled",
		RelatedEntityType: "sponsorships",
		RelatedEntityID:   sponsorshipID,
		Title: LocalText{
			En:  "Sponsorship cancelled",
			Ar:  "تم إلغاء الكفالة",
			Ckb: "سپۆنسەرکردن هەڵوەشێنرایەوە",
			Kmr: "سپۆنسەری هاتە بەتالکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your monthly sponsorship for %s was cancelled.", projectName),
			Ar:  fmt.Sprintf("تم إلغاء كفالتك الشهرية للمشروع \"%s\".", projectName),
			Ckb: fmt.Sprintf("سپۆنسەری مانگانەی تۆ بۆ «%s» هەڵوەشێنرایەوە.", projectName),
			Kmr: fmt.Sprintf("سپۆنسەریا تە یا مەهانە بۆ «%s» هاتە بەتالکرن.", projectName),
		},
	}
}

// InKindSubmittedMsg — donor created an in-kind donation pending pickup.
func InKindSubmittedMsg(itemName string, inKindID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "in_kind_donation_submitted",
		RelatedEntityType: "in_kind_donations",
		RelatedEntityID:   inKindID,
		Title: LocalText{
			En:  "In-kind donation submitted",
			Ar:  "تم إرسال التبرع العيني",
			Ckb: "بەخشینی ماددی نێردرا",
			Kmr: "بەخشینا مادی هاتە شاندن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your in-kind donation \"%s\" was sent for admin review.", itemName),
			Ar:  fmt.Sprintf("تم إرسال تبرعك العيني \"%s\" إلى المسؤول للمراجعة.", itemName),
			Ckb: fmt.Sprintf("بەخشینی ماددی «%s» بۆ پێداچوونەوەی بەڕێوەبەر نێردرا.", itemName),
			Kmr: fmt.Sprintf("بەخشینا مادی «%s» بۆ پشکنینا بەرپرسی هاتە شاندن.", itemName),
		},
	}
}

// MarketplaceOrderSubmittedMsg — donor placed a marketplace order.
func MarketplaceOrderSubmittedMsg(orderID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "marketplace_order_submitted",
		RelatedEntityType: "marketplace_orders",
		RelatedEntityID:   orderID,
		Title: LocalText{
			En:  "Marketplace order submitted",
			Ar:  "تم إرسال طلب المتجر",
			Ckb: "داوای بازاڕ نێردرا",
			Kmr: "داخوازا بازاڕی هاتە شاندن",
		},
		Body: LocalText{
			En:  "Your marketplace order was sent for admin review.",
			Ar:  "تم إرسال طلبك في المتجر إلى المسؤول للمراجعة.",
			Ckb: "داواکاری تۆ لە بازاڕ بۆ پێداچوونەوەی بەڕێوەبەر نێردرا.",
			Kmr: "داخوازا تە یا بازاڕی بۆ پشکنینا بەرپرسی هاتە شاندن.",
		},
	}
}

// SupportSubmittedMsg — any user filed a support ticket.
func SupportSubmittedMsg(subject string, ticketID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "support_request_submitted",
		RelatedEntityType: "support_tickets",
		RelatedEntityID:   ticketID,
		Title: LocalText{
			En:  "Support request submitted",
			Ar:  "تم إرسال طلب الدعم",
			Ckb: "داواکاری پشتگیری نێردرا",
			Kmr: "داخوازا پشتگیریێ هاتە شاندن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your support request \"%s\" was sent to the team.", subject),
			Ar:  fmt.Sprintf("تم إرسال طلب الدعم الخاص بك \"%s\" إلى الفريق.", subject),
			Ckb: fmt.Sprintf("داواکاری پشتگیریت «%s» بۆ تیمەکە نێردرا.", subject),
			Kmr: fmt.Sprintf("داخوازا تە یا پشتگیریێ «%s» بۆ تیمێ هاتە شاندن.", subject),
		},
	}
}

// MarriageSubmittedMsg — user submitted a marriage service profile.
func MarriageSubmittedMsg(profileCode string, profileID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "marriage_profile_submitted",
		RelatedEntityType: "marriage_profiles",
		RelatedEntityID:   profileID,
		Title: LocalText{
			En:  "Marriage service submitted",
			Ar:  "تم إرسال خدمة الزواج",
			Ckb: "خزمەتگوزاری هاوسەرگیری نێردرا",
			Kmr: "خزمەتگوزاریا زەواجێ هاتە شاندن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your marriage service profile %s was sent for admin review.", profileCode),
			Ar:  fmt.Sprintf("تم إرسال ملف خدمة الزواج الخاص بك %s إلى المسؤول للمراجعة.", profileCode),
			Ckb: fmt.Sprintf("پرۆفایلی خزمەتگوزاری هاوسەرگیریت %s بۆ پێداچوونەوەی بەڕێوەبەر نێردرا.", profileCode),
			Kmr: fmt.Sprintf("پرۆفایلا تە یا خزمەتگوزاریا زەواجێ %s بۆ پشکنینا بەرپرسی هاتە شاندن.", profileCode),
		},
	}
}

// BeneficiaryCaseSubmittedMsg — beneficiary submitted a new case.
func BeneficiaryCaseSubmittedMsg(title string, caseID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "beneficiary_case_submitted",
		RelatedEntityType: "beneficiary_cases",
		RelatedEntityID:   caseID,
		Title: LocalText{
			En:  "Beneficiary case submitted",
			Ar:  "تم إرسال حالة المستفيد",
			Ckb: "دۆسیەی سوودمەند نێردرا",
			Kmr: "دۆسیا هەژاری هاتە شاندن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your beneficiary case \"%s\" was sent for admin review.", title),
			Ar:  fmt.Sprintf("تم إرسال حالتك \"%s\" إلى المسؤول للمراجعة.", title),
			Ckb: fmt.Sprintf("دۆسیە سوودمەندیت «%s» بۆ پێداچوونەوەی بەڕێوەبەر نێردرا.", title),
			Kmr: fmt.Sprintf("دۆسیا تە یا هەژاری «%s» بۆ پشکنینا بەرپرسی هاتە شاندن.", title),
		},
	}
}

// VolunteerApplicationSubmittedMsg — volunteer just filled out the
// application form (POST /api/volunteers action=apply). Acknowledges
// receipt so the volunteer knows we got it before admin reviews.
//
// Phase 21b.
func VolunteerApplicationSubmittedMsg(applicantName string, appID int64) LocalizedMessage {
	displayName := applicantName
	if displayName == "" {
		displayName = "your application"
	}
	return LocalizedMessage{
		Type:              "volunteer_application_submitted",
		RelatedEntityType: "volunteer_applications",
		RelatedEntityID:   appID,
		Title: LocalText{
			En:  "Application received",
			Ar:  "تم استلام طلب التطوع",
			Ckb: "داواکاری خۆبەخشی وەرگیرا",
			Kmr: "داخوازا خۆبەخشیێ هاتە وەرگرتن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your volunteer application for %s was received and is being reviewed. We'll notify you when it's approved.", displayName),
			Ar:  fmt.Sprintf("تم استلام طلب التطوع الخاص بـ %s وهو قيد المراجعة. سنبلغك عندما تتم الموافقة عليه.", displayName),
			Ckb: fmt.Sprintf("داواکاری خۆبەخشی بۆ %s وەرگیرا و لە پێداچوونەوەدایە. کاتێک پەسەند کرا ئاگادارت دەکەینەوە.", displayName),
			Kmr: fmt.Sprintf("داخوازا خۆبەخشیێ بۆ %s هاتە وەرگرتن و د پشکنینێ دایە. دەمێ هاتە قبوولکرن، تە ئاگەهدار دکەین.", displayName),
		},
	}
}

// VolunteerMissionJoinSubmittedMsg — volunteer just clicked "Join" on a
// specific mission (POST /api/volunteers action=join_mission). Tells them
// the request is in the admin's queue and they'll hear back.
//
// Different from MissionSignupDecisionMsg, which fires AFTER the admin
// decides; this one fires the moment the request is submitted, mirroring
// the donor / beneficiary submit acknowledgements.
//
// Phase 21b.
func VolunteerMissionJoinSubmittedMsg(missionTitle string, signupID int64) LocalizedMessage {
	displayMission := missionTitle
	if displayMission == "" {
		displayMission = "this mission"
	}
	return LocalizedMessage{
		Type:              "volunteer_mission_join_submitted",
		RelatedEntityType: "volunteer_mission_signups",
		RelatedEntityID:   signupID,
		Title: LocalText{
			En:  "Join request received",
			Ar:  "تم استلام طلب الانضمام",
			Ckb: "داواکاری بەشداری وەرگیرا",
			Kmr: "داخوازا بەشداریێ هاتە وەرگرتن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your request to join \"%s\" was received and is being reviewed. We'll notify you when it's approved.", displayMission),
			Ar:  fmt.Sprintf("تم استلام طلبك للانضمام إلى \"%s\" وهو قيد المراجعة. سنبلغك عندما تتم الموافقة عليه.", displayMission),
			Ckb: fmt.Sprintf("داواکاری بەشداریت بۆ «%s» وەرگیرا و لە پێداچوونەوەدایە. کاتێک پەسەند کرا ئاگادارت دەکەینەوە.", displayMission),
			Kmr: fmt.Sprintf("داخوازا تە یا بەشداریێ بۆ «%s» هاتە وەرگرتن و د پشکنینێ دایە. دەمێ هاتە قبوولکرن، تە ئاگەهدار دکەین.", displayMission),
		},
	}
}

// ProjectRequestSubmittedMsg — beneficiary submitted a project funding request.
func ProjectRequestSubmittedMsg(title string, requestID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "project_request_submitted",
		RelatedEntityType: "beneficiary_project_requests",
		RelatedEntityID:   requestID,
		Title: LocalText{
			En:  "Project request submitted",
			Ar:  "تم إرسال طلب المشروع",
			Ckb: "داوای پڕۆژە نێردرا",
			Kmr: "داخوازا پرۆژەیێ هاتە شاندن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your project request \"%s\" was sent for admin review.", title),
			Ar:  fmt.Sprintf("تم إرسال طلب مشروعك \"%s\" إلى المسؤول للمراجعة.", title),
			Ckb: fmt.Sprintf("داواکاری پڕۆژەکەت «%s» بۆ پێداچوونەوەی بەڕێوەبەر نێردرا.", title),
			Kmr: fmt.Sprintf("داخوازا تە یا پرۆژەیێ «%s» بۆ پشکنینا بەرپرسی هاتە شاندن.", title),
		},
	}
}

// ============================================================================
// DECISION TEMPLATES — admin acted on a row; user gets notified. These are
// the ~24 triggers that were silently lost in the PHP→Go port.
// ============================================================================

// --- Registration approval -------------------------------------------------

// RegistrationApprovedMsg — admin approved a new user's registration, so they
// can now enter the app.
func RegistrationApprovedMsg(userID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "registration_approved",
		RelatedEntityType: "users",
		RelatedEntityID:   userID,
		Title: LocalText{
			En:  "Account approved",
			Ar:  "تمت الموافقة على الحساب",
			Ckb: "هەژمارەکە پەسەندکرا",
			Kmr: "هەژمار هاتە پەسەندکرن",
		},
		Body: LocalText{
			En:  "An admin approved your account. You can now sign in and use the app.",
			Ar:  "وافق المشرف على حسابك. يمكنك الآن تسجيل الدخول واستخدام التطبيق.",
			Ckb: "بەڕێوەبەرێک هەژمارەکەتی پەسەند کرد. ئێستا دەتوانیت بچیتە ژوورەوە و ئەپەکە بەکاربهێنیت.",
			Kmr: "بەڕێڤەبەرەکی هەژمارێ تە پەسەند کر. نوکە تو دشێی بکەڤیە ژوورێ و ئەپلیکەیشنێ بکاربینی.",
		},
	}
}

// RegistrationRejectedMsg — admin rejected the registration; the user may edit
// their details and submit again. reason is optional.
func RegistrationRejectedMsg(userID int64, reason string) LocalizedMessage {
	reason = strings.TrimSpace(reason)
	enTail, arTail, ckbTail, kmrTail := "", "", "", ""
	if reason != "" {
		enTail = fmt.Sprintf(" Reason: %s", reason)
		arTail = fmt.Sprintf(" السبب: %s", reason)
		ckbTail = fmt.Sprintf(" هۆکار: %s", reason)
		kmrTail = fmt.Sprintf(" ئەگەر: %s", reason)
	}
	return LocalizedMessage{
		Type:              "registration_rejected",
		RelatedEntityType: "users",
		RelatedEntityID:   userID,
		Title: LocalText{
			En:  "Registration needs changes",
			Ar:  "التسجيل يحتاج إلى تعديل",
			Ckb: "تۆمارکردن پێویستی بە گۆڕانکاری هەیە",
			Kmr: "تۆمارکرن پێدڤی ب گهۆرینان هەیە",
		},
		Body: LocalText{
			En:  "Your registration wasn't approved. Please review your details and submit again." + enTail,
			Ar:  "لم تتم الموافقة على تسجيلك. يرجى مراجعة بياناتك وإرسالها مرة أخرى." + arTail,
			Ckb: "تۆمارکردنەکەت پەسەند نەکرا. تکایە زانیاریەکانت پێداچوونەوە بکە و دووبارە بینێرە." + ckbTail,
			Kmr: "تۆمارکرنا تە نەهاتە پەسەندکرن. ژ کەرەما خۆ زانیاریێن خۆ ببینە و دیسا بشینە." + kmrTail,
		},
	}
}

// --- Donations -------------------------------------------------------------

// formatPercent renders a "(P% of goal)" suffix when goal is positive,
// otherwise an empty string. Kept here so the same formatting logic is
// reused by all donation templates.
func formatPercent(raised, goal float64) string {
	if goal <= 0 {
		return ""
	}
	pct := raised / goal * 100
	if pct > 100 {
		pct = 100
	}
	return fmt.Sprintf(" (%.0f%% of goal)", pct)
}

// formatPercentAr / formatPercentKurd — same logic, locale-specific suffix
// so the Arabic / Kurdish reads naturally rather than swapping in EN words.
func formatPercentAr(raised, goal float64) string {
	if goal <= 0 {
		return ""
	}
	pct := raised / goal * 100
	if pct > 100 {
		pct = 100
	}
	return fmt.Sprintf(" (%.0f%% من الهدف)", pct)
}
func formatPercentKurd(raised, goal float64) string {
	if goal <= 0 {
		return ""
	}
	pct := raised / goal * 100
	if pct > 100 {
		pct = 100
	}
	// Same suffix works for both Sorani and Badini (number + percent + "from
	// the goal" written with the Sorani word; reads correctly in both).
	return fmt.Sprintf(" (%.0f%% لە ئامانج)", pct)
}

// DonationCancelledByDonorMsg — confirmation when a donor self-cancels a
// pending donation (POST /api/donate/:id/cancel). Phase 23.
func DonationCancelledByDonorMsg(amount, currency, campaignName string, donationID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "donation_cancelled_by_donor",
		RelatedEntityType: "donations",
		RelatedEntityID:   donationID,
		Title: LocalText{
			En:  "Donation cancelled",
			Ar:  "تم إلغاء التبرع",
			Ckb: "بەخشینەکە هەڵوەشێنرایەوە",
			Kmr: "بەخشین هاتە بەتالکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your %s %s donation to \"%s\" was cancelled. The campaign total has been adjusted.", amount, currency, campaignName),
			Ar:  fmt.Sprintf("تم إلغاء تبرعك بمبلغ %s %s للحملة \"%s\". تم تعديل إجمالي الحملة.", amount, currency, campaignName),
			Ckb: fmt.Sprintf("بەخشینەکەت بە بڕی %s %s بۆ «%s» هەڵوەشایەوە. کۆی هەڵمەتەکە ڕێکخرایەوە.", amount, currency, campaignName),
			Kmr: fmt.Sprintf("بەخشینا تە یا %s %s بۆ «%s» هاتە بەتالکرن. کۆیا کەمپانیێ هاتە رێکخستن.", amount, currency, campaignName),
		},
	}
}

// DonationApprovedMsg — admin marked a donation as approved/received/delivered.
// Body shows: donor amount + which campaign + the campaign's NEW running total
// after this donation + percent funded. raisedAmount and goalAmount are
// strings (the column types are varchar) but expected to parse as numbers.
func DonationApprovedMsg(amount, currency, campaignName, raisedAmount, goalAmount string, donationID int64) LocalizedMessage {
	// Parse numerics best-effort so we can compute percent + reformat with
	// thousands separators. If they don't parse, fall back to the raw strings.
	var raised, goal float64
	fmt.Sscanf(raisedAmount, "%f", &raised)
	fmt.Sscanf(goalAmount, "%f", &goal)

	raisedDisp := formatThousands(raised, raisedAmount)
	goalDisp := formatThousands(goal, goalAmount)

	return LocalizedMessage{
		Type:              "donation_approved",
		RelatedEntityType: "donations",
		RelatedEntityID:   donationID,
		Title: LocalText{
			En:  "Donation approved",
			Ar:  "تمت الموافقة على التبرع",
			Ckb: "بەخشینەکە پەسەند کرا",
			Kmr: "بەخشین قبوول کر",
		},
		Body: LocalText{
			En: fmt.Sprintf(
				"Your %s %s donation to \"%s\" was approved. The campaign has now raised %s of %s %s%s. Thank you!",
				amount, currency, campaignName, raisedDisp, goalDisp, currency, formatPercent(raised, goal),
			),
			Ar: fmt.Sprintf(
				"تمت الموافقة على تبرعك بمبلغ %s %s للحملة \"%s\". جمعت الحملة الآن %s من أصل %s %s%s. شكراً لك!",
				amount, currency, campaignName, raisedDisp, goalDisp, currency, formatPercentAr(raised, goal),
			),
			Ckb: fmt.Sprintf(
				"بەخشینەکەت بە بڕی %s %s بۆ «%s» پەسەند کرا. هەڵمەتەکە ئێستا %s لە %s %s کۆکردووەتەوە%s. سوپاس!",
				amount, currency, campaignName, raisedDisp, goalDisp, currency, formatPercentKurd(raised, goal),
			),
			Kmr: fmt.Sprintf(
				"بەخشینا تە یا %s %s بۆ «%s» هاتە قبوولکرن. کەمپانیا نوکە %s ژ %s %s کۆ کریە%s. سپاس!",
				amount, currency, campaignName, raisedDisp, goalDisp, currency, formatPercentKurd(raised, goal),
			),
		},
	}
}

// DonationRejectedMsg — admin rejected a donation entry. Body still shows the
// amount + campaign so the donor remembers which donation this is about.
func DonationRejectedMsg(amount, currency, campaignName string, donationID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "donation_rejected",
		RelatedEntityType: "donations",
		RelatedEntityID:   donationID,
		Title: LocalText{
			En:  "Donation rejected",
			Ar:  "تم رفض التبرع",
			Ckb: "بەخشینەکە ڕەتکرایەوە",
			Kmr: "بەخشین هاتە رەتکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your %s %s donation to \"%s\" was rejected by the admin. Please contact support for details.", amount, currency, campaignName),
			Ar:  fmt.Sprintf("تم رفض تبرعك بمبلغ %s %s للحملة \"%s\" من قِبَل المسؤول. يرجى التواصل مع الدعم للمزيد من التفاصيل.", amount, currency, campaignName),
			Ckb: fmt.Sprintf("بەخشینەکەت بە بڕی %s %s بۆ «%s» لەلایەن بەڕێوەبەرەوە ڕەتکرایەوە. تکایە بۆ وردەکاری زیاتر پەیوەندی بە پشتگیریەوە بکە.", amount, currency, campaignName),
			Kmr: fmt.Sprintf("بەخشینا تە یا %s %s بۆ «%s» ژلایێ بەرپرسی ڤە هاتە رەتکرن. ژکەرەما خۆ بۆ زانیاریا زێدەتر دگەل پشتگیریێ پەیوەندیێ بکە.", amount, currency, campaignName),
		},
	}
}

// DonationPaymentConfirmedMsg — Phase 27.2 — admin set payment_status=1
// (success), i.e. they've verified the donor's payment was received. This
// is the most common "accept" action triggered from the donations admin
// page — before this template existed, that click was silent and the
// donor got no push.
//
// Distinct from DonationApprovedMsg (which fires on delivery_status =
// received/delivered) so both can land without dedup conflict; one is the
// payment confirmation, the other is the field-delivery confirmation.
func DonationPaymentConfirmedMsg(amount, currency, campaignName string, donationID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "donation_payment_confirmed",
		RelatedEntityType: "donations",
		RelatedEntityID:   donationID,
		Title: LocalText{
			En:  "Donation confirmed",
			Ar:  "تم تأكيد التبرع",
			Ckb: "بەخشینەکە پشتڕاست کرایەوە",
			Kmr: "بەخشین هاتە پشتراستکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your %s %s donation to \"%s\" was confirmed by the team. Thank you for your support!", amount, currency, campaignName),
			Ar:  fmt.Sprintf("تم تأكيد تبرعك بمبلغ %s %s للحملة \"%s\" من قِبَل الفريق. شكراً لدعمك!", amount, currency, campaignName),
			Ckb: fmt.Sprintf("بەخشینەکەت بە بڕی %s %s بۆ «%s» لەلایەن تیمەوە پشتڕاست کرایەوە. سوپاس بۆ پشتگیریت!", amount, currency, campaignName),
			Kmr: fmt.Sprintf("بەخشینا تە یا %s %s بۆ «%s» ژلایێ تیمێ ڤە هاتە پشتراستکرن. سپاس بۆ پشتگیریا تە!", amount, currency, campaignName),
		},
	}
}

// DonationPaymentFailedMsg — Phase 27.2 — admin set payment_status=3
// (failed), i.e. they couldn't verify the donor's payment or it was
// rejected by the payment processor. Donor needs to know so they can
// resend or follow up.
func DonationPaymentFailedMsg(amount, currency, campaignName string, donationID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "donation_payment_failed",
		RelatedEntityType: "donations",
		RelatedEntityID:   donationID,
		Title: LocalText{
			En:  "Donation could not be confirmed",
			Ar:  "تعذّر تأكيد التبرع",
			Ckb: "نەکرا بەخشینەکە پشتڕاست بکرێتەوە",
			Kmr: "نەشیا بەخشین بێتە پشتراستکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("We couldn't confirm your %s %s donation to \"%s\". Please contact support so we can sort it out.", amount, currency, campaignName),
			Ar:  fmt.Sprintf("لم نتمكن من تأكيد تبرعك بمبلغ %s %s للحملة \"%s\". يرجى التواصل مع الدعم للمتابعة.", amount, currency, campaignName),
			Ckb: fmt.Sprintf("نەمانتوانی بەخشینەکەت بە بڕی %s %s بۆ «%s» پشتڕاست بکەینەوە. تکایە پەیوەندی بە پشتگیری بکە.", amount, currency, campaignName),
			Kmr: fmt.Sprintf("مە نەشیا بەخشینا تە یا %s %s بۆ «%s» پشتراست بکەین. ژکەرەما خۆ دگەل پشتگیریێ پەیوەندیێ بکە.", amount, currency, campaignName),
		},
	}
}

// formatThousands renders a number with comma separators (e.g. 200,000).
// Falls back to the raw string when the numeric parse failed so we never
// accidentally print "0" for an unparseable value.
func formatThousands(n float64, raw string) string {
	if n <= 0 && raw != "" {
		return raw
	}
	// Build the integer with thousands separators by walking the string.
	whole := fmt.Sprintf("%.0f", n)
	if len(whole) <= 3 {
		return whole
	}
	out := ""
	for i, c := range whole {
		if i > 0 && (len(whole)-i)%3 == 0 {
			out += ","
		}
		out += string(c)
	}
	return out
}

// DonationReceivedOnProjectMsg — fires on the beneficiary (project owner)
// every time a donor donates to their project. Matches old PHP behavior.
func DonationReceivedOnProjectMsg(amount, currency, projectTitle, donorName string, donationID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "donation_received_on_project",
		RelatedEntityType: "donations",
		RelatedEntityID:   donationID,
		Title: LocalText{
			En:  "New donation received",
			Ar:  "تم استلام تبرع جديد",
			Ckb: "بەخشینێکی نوێ گەیشت",
			Kmr: "بەخشینەکا نوو هاتە وەرگرتن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("%s donated %s %s to your project \"%s\". Thank them when you can!", donorName, amount, currency, projectTitle),
			Ar:  fmt.Sprintf("تبرع %s بمبلغ %s %s لمشروعك \"%s\". شكراً لمساعدتك!", donorName, amount, currency, projectTitle),
			Ckb: fmt.Sprintf("%s بڕی %s %s بەخشییە بۆ پڕۆژەکەت «%s». سوپاسی بکە کاتێک دەتوانیت!", donorName, amount, currency, projectTitle),
			Kmr: fmt.Sprintf("%s بڕێ %s %s بەخشاندە بۆ پرۆژا تە «%s». دەمێ بشێی سپاسیێ بکە!", donorName, amount, currency, projectTitle),
		},
	}
}

// --- Sponsorships ----------------------------------------------------------

// SponsorshipAcceptedMsg — admin accepted a pending sponsorship → active.
func SponsorshipAcceptedMsg(amount, currency, projectName string, sponsorshipID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "sponsorship_accepted",
		RelatedEntityType: "sponsorships",
		RelatedEntityID:   sponsorshipID,
		Title: LocalText{
			En:  "Sponsorship accepted",
			Ar:  "تم قبول الكفالة",
			Ckb: "سپۆنسەرکردن وەرگیرا",
			Kmr: "سپۆنسەری هاتە قبوولکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your %s %s monthly sponsorship for \"%s\" was accepted. You'll be reminded each month when payment is due.", amount, currency, projectName),
			Ar:  fmt.Sprintf("تم قبول كفالتك الشهرية بمبلغ %s %s للمشروع \"%s\". سيتم تذكيرك كل شهر عند موعد الدفع.", amount, currency, projectName),
			Ckb: fmt.Sprintf("سپۆنسەری مانگانەی تۆ بە بڕی %s %s بۆ «%s» وەرگیرا. هەموو مانگێک کاتی پارەدان پێشت ئاگادار دەکرێیتەوە.", amount, currency, projectName),
			Kmr: fmt.Sprintf("سپۆنسەریا تە یا مەهانە یا %s %s بۆ «%s» هاتە قبوولکرن. هەر مەهی دەمێ پارەدانێ تە ئاگەهدار دکەین.", amount, currency, projectName),
		},
	}
}

// SponsorshipStatusChangedMsg — generic fallback when admin moves the
// sponsorship to a status other than 'active' or 'cancelled'.
func SponsorshipStatusChangedMsg(projectName, status string, sponsorshipID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "sponsorship_status_changed",
		RelatedEntityType: "sponsorships",
		RelatedEntityID:   sponsorshipID,
		Title: LocalText{
			En:  "Sponsorship status updated",
			Ar:  "تم تحديث حالة الكفالة",
			Ckb: "بارودۆخی سپۆنسەرکردن نوێ کرایەوە",
			Kmr: "ڕەوشا سپۆنسەریێ هاتە نوێکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your monthly sponsorship for \"%s\" is now %s.", projectName, status),
			Ar:  fmt.Sprintf("كفالتك الشهرية للمشروع \"%s\" أصبحت الآن %s.", projectName, status),
			Ckb: fmt.Sprintf("سپۆنسەری مانگانەی تۆ بۆ «%s» ئێستا %s ە.", projectName, status),
			Kmr: fmt.Sprintf("سپۆنسەریا تە یا مەهانە بۆ «%s» نوکە %s یە.", projectName, status),
		},
	}
}

// --- Marketplace orders ----------------------------------------------------

// MarketplaceOrderApprovedMsg — admin approved a pending order.
func MarketplaceOrderApprovedMsg(productName string, qty int, total, currency string, orderID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "marketplace_order_approved",
		RelatedEntityType: "marketplace_orders",
		RelatedEntityID:   orderID,
		Title: LocalText{
			En:  "Marketplace order approved",
			Ar:  "تمت الموافقة على طلب المتجر",
			Ckb: "داوای بازاڕ پەسەند کرا",
			Kmr: "داخوازا بازاڕی هاتە قبوولکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your order for %d × %s (%s %s) was approved and is being processed.", qty, productName, total, currency),
			Ar:  fmt.Sprintf("تمت الموافقة على طلبك لـ %d × %s (%s %s) وجاري معالجته الآن.", qty, productName, total, currency),
			Ckb: fmt.Sprintf("داواکاری تۆ بۆ %d × %s (%s %s) پەسەند کرا و ئێستا لە چاوەڕێداپە.", qty, productName, total, currency),
			Kmr: fmt.Sprintf("داخوازا تە بۆ %d × %s (%s %s) هاتە قبوولکرن و نوکە لێ تێ گەرین.", qty, productName, total, currency),
		},
	}
}

// MarketplaceOrderCompletedMsg — admin marked order delivered/completed.
func MarketplaceOrderCompletedMsg(productName string, qty int, orderID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "marketplace_order_completed",
		RelatedEntityType: "marketplace_orders",
		RelatedEntityID:   orderID,
		Title: LocalText{
			En:  "Marketplace order completed",
			Ar:  "تم إكمال طلب المتجر",
			Ckb: "داوای بازاڕ تەواو کرا",
			Kmr: "داخوازا بازاڕی هاتە تەواوکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your order for %d × %s has been delivered. Thank you!", qty, productName),
			Ar:  fmt.Sprintf("تم تسليم طلبك لـ %d × %s. شكراً لك!", qty, productName),
			Ckb: fmt.Sprintf("داواکاری تۆ بۆ %d × %s گەیەنرا. سوپاس!", qty, productName),
			Kmr: fmt.Sprintf("داخوازا تە بۆ %d × %s هاتە گەهاندن. سپاس!", qty, productName),
		},
	}
}

// MarketplaceOrderCancelledMsg — admin cancelled an order.
func MarketplaceOrderCancelledMsg(productName string, qty int, orderID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "marketplace_order_cancelled",
		RelatedEntityType: "marketplace_orders",
		RelatedEntityID:   orderID,
		Title: LocalText{
			En:  "Marketplace order cancelled",
			Ar:  "تم إلغاء طلب المتجر",
			Ckb: "داوای بازاڕ هەڵوەشێنرایەوە",
			Kmr: "داخوازا بازاڕی هاتە بەتالکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your order for %d × %s was cancelled. Please contact support for details.", qty, productName),
			Ar:  fmt.Sprintf("تم إلغاء طلبك لـ %d × %s. يرجى التواصل مع الدعم للمزيد من التفاصيل.", qty, productName),
			Ckb: fmt.Sprintf("داواکاری تۆ بۆ %d × %s هەڵوەشایەوە. تکایە پەیوەندی بە پشتگیریەوە بکە.", qty, productName),
			Kmr: fmt.Sprintf("داخوازا تە بۆ %d × %s هاتە بەتالکرن. ژکەرەما خۆ دگەل پشتگیریێ پەیوەندیێ بکە.", qty, productName),
		},
	}
}

// --- In-kind donations (admin decision) ---------------------------------
//
// Phase 23 — proper templates per lifecycle state, with the real quantity
// substituted into the body. Replaces the Phase 18 shortcut that borrowed
// the marketplace templates and hardcoded "1 × item".
//
// quantityLine renders "(qty 25 boxes)" or "(qty 1)" or "" when qty is empty.
func quantityLine(qty string) string {
	q := strings.TrimSpace(qty)
	if q == "" {
		return ""
	}
	return " (qty " + q + ")"
}

// InKindScheduledMsg — admin marked the in-kind row as scheduled for pickup.
func InKindScheduledMsg(itemName, qty string, inKindID int64) LocalizedMessage {
	q := quantityLine(qty)
	return LocalizedMessage{
		Type:              "in_kind_donation_scheduled",
		RelatedEntityType: "in_kind_donations",
		RelatedEntityID:   inKindID,
		Title: LocalText{
			En:  "In-kind donation scheduled",
			Ar:  "تم جدولة التبرع العيني",
			Ckb: "بەخشینی ماددی کاتی دیاری کرا",
			Kmr: "بەخشینا مادی هاتە پلانکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your in-kind donation \"%s\"%s is scheduled for pickup. We'll be in touch about the timing.", itemName, q),
			Ar:  fmt.Sprintf("تم جدولة تبرعك العيني \"%s\"%s للاستلام. سنتواصل معك بشأن التوقيت.", itemName, q),
			Ckb: fmt.Sprintf("بەخشینی ماددیت «%s»%s کاتی وەرگرتنی دیاری کراوە. لەسەر کات پەیوەندیت پێوە دەکەین.", itemName, q),
			Kmr: fmt.Sprintf("بەخشینا تە یا مادی «%s»%s هاتە پلانکرن بۆ وەرگرتن. ل سەر دەمی دگەل تە پەیوەندیێ دکەین.", itemName, q),
		},
	}
}

// InKindReceivedMsg — admin marked the donation as received (in our hands).
func InKindReceivedMsg(itemName, qty string, inKindID int64) LocalizedMessage {
	q := quantityLine(qty)
	return LocalizedMessage{
		Type:              "in_kind_donation_received",
		RelatedEntityType: "in_kind_donations",
		RelatedEntityID:   inKindID,
		Title: LocalText{
			En:  "In-kind donation received",
			Ar:  "تم استلام التبرع العيني",
			Ckb: "بەخشینی ماددی وەرگیرا",
			Kmr: "بەخشینا مادی هاتە وەرگرتن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("We've received your in-kind donation \"%s\"%s. Thank you!", itemName, q),
			Ar:  fmt.Sprintf("استلمنا تبرعك العيني \"%s\"%s. شكراً لك!", itemName, q),
			Ckb: fmt.Sprintf("بەخشینی ماددیت «%s»%s مان وەرگرت. سوپاس!", itemName, q),
			Kmr: fmt.Sprintf("بەخشینا تە یا مادی «%s»%s مە وەرگرت. سپاس!", itemName, q),
		},
	}
}

// InKindDeliveredMsg — admin delivered the donation to the beneficiary.
func InKindDeliveredMsg(itemName, qty string, inKindID int64) LocalizedMessage {
	q := quantityLine(qty)
	return LocalizedMessage{
		Type:              "in_kind_donation_delivered",
		RelatedEntityType: "in_kind_donations",
		RelatedEntityID:   inKindID,
		Title: LocalText{
			En:  "In-kind donation delivered",
			Ar:  "تم تسليم التبرع العيني",
			Ckb: "بەخشینی ماددی گەیەنرا",
			Kmr: "بەخشینا مادی هاتە گەهاندن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your in-kind donation \"%s\"%s has been delivered to those in need. Your support made it real.", itemName, q),
			Ar:  fmt.Sprintf("تم تسليم تبرعك العيني \"%s\"%s إلى المحتاجين. دعمك جعل هذا حقيقياً.", itemName, q),
			Ckb: fmt.Sprintf("بەخشینی ماددیت «%s»%s گەیەنرا بە کەسانی پێویستی. پشتگیریت ئەمەی کردە ڕاستی.", itemName, q),
			Kmr: fmt.Sprintf("بەخشینا تە یا مادی «%s»%s هاتە گەهاندن بۆ وان ێن پێدڤی. پشتگیریا تە ئەڤە کرە ڕاستی.", itemName, q),
		},
	}
}

// InKindCancelledMsg — admin cancelled the donation (couldn't be processed).
func InKindCancelledMsg(itemName, qty string, inKindID int64) LocalizedMessage {
	q := quantityLine(qty)
	return LocalizedMessage{
		Type:              "in_kind_donation_cancelled",
		RelatedEntityType: "in_kind_donations",
		RelatedEntityID:   inKindID,
		Title: LocalText{
			En:  "In-kind donation cancelled",
			Ar:  "تم إلغاء التبرع العيني",
			Ckb: "بەخشینی ماددی هەڵوەشێنرایەوە",
			Kmr: "بەخشینا مادی هاتە بەتالکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your in-kind donation \"%s\"%s was cancelled. Please contact support for details.", itemName, q),
			Ar:  fmt.Sprintf("تم إلغاء تبرعك العيني \"%s\"%s. يرجى التواصل مع الدعم للمزيد من التفاصيل.", itemName, q),
			Ckb: fmt.Sprintf("بەخشینی ماددیت «%s»%s هەڵوەشێنرایەوە. تکایە پەیوەندی بە پشتگیریەوە بکە.", itemName, q),
			Kmr: fmt.Sprintf("بەخشینا تە یا مادی «%s»%s هاتە بەتالکرن. ژکەرەما خۆ دگەل پشتگیریێ پەیوەندیێ بکە.", itemName, q),
		},
	}
}

// --- Marriage profiles -----------------------------------------------------

// MarriageApprovedMsg — admin approved a marriage service profile.
func MarriageApprovedMsg(profileCode string, profileID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "marriage_approved",
		RelatedEntityType: "marriage_profiles",
		RelatedEntityID:   profileID,
		Title: LocalText{
			En:  "Marriage profile approved",
			Ar:  "تمت الموافقة على ملف الزواج",
			Ckb: "پرۆفایلی هاوسەرگیری پەسەند کرا",
			Kmr: "پرۆفایلا زەواجێ هاتە قبوولکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your marriage profile %s was approved and is now visible.", profileCode),
			Ar:  fmt.Sprintf("تمت الموافقة على ملف الزواج الخاص بك %s وأصبح ظاهراً الآن.", profileCode),
			Ckb: fmt.Sprintf("پرۆفایلی هاوسەرگیریت %s پەسەند کرا و ئێستا دیارە.", profileCode),
			Kmr: fmt.Sprintf("پرۆفایلا تە یا زەواجێ %s هاتە قبوولکرن و نوکە دیار ە.", profileCode),
		},
	}
}

// MarriageRejectedMsg — admin rejected a marriage profile.
func MarriageRejectedMsg(profileCode string, profileID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "marriage_rejected",
		RelatedEntityType: "marriage_profiles",
		RelatedEntityID:   profileID,
		Title: LocalText{
			En:  "Marriage profile rejected",
			Ar:  "تم رفض ملف الزواج",
			Ckb: "پرۆفایلی هاوسەرگیری ڕەتکرایەوە",
			Kmr: "پرۆفایلا زەواجێ هاتە رەتکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your marriage profile %s was rejected. Please contact support for details.", profileCode),
			Ar:  fmt.Sprintf("تم رفض ملف الزواج الخاص بك %s. يرجى التواصل مع الدعم للمزيد من التفاصيل.", profileCode),
			Ckb: fmt.Sprintf("پرۆفایلی هاوسەرگیریت %s ڕەتکرایەوە. تکایە پەیوەندی بە پشتگیریەوە بکە.", profileCode),
			Kmr: fmt.Sprintf("پرۆفایلا تە یا زەواجێ %s هاتە رەتکرن. ژکەرەما خۆ دگەل پشتگیریێ پەیوەندیێ بکە.", profileCode),
		},
	}
}

// MarriageStatusChangedMsg — generic fallback for other status changes.
func MarriageStatusChangedMsg(profileCode, status string, profileID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "marriage_status_changed",
		RelatedEntityType: "marriage_profiles",
		RelatedEntityID:   profileID,
		Title: LocalText{
			En:  "Marriage profile updated",
			Ar:  "تم تحديث ملف الزواج",
			Ckb: "پرۆفایلی هاوسەرگیری نوێ کرایەوە",
			Kmr: "پرۆفایلا زەواجێ هاتە نوێکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your marriage profile %s is now %s.", profileCode, status),
			Ar:  fmt.Sprintf("ملف الزواج الخاص بك %s أصبح الآن %s.", profileCode, status),
			Ckb: fmt.Sprintf("پرۆفایلی هاوسەرگیریت %s ئێستا %s ە.", profileCode, status),
			Kmr: fmt.Sprintf("پرۆفایلا تە یا زەواجێ %s نوکە %s یە.", profileCode, status),
		},
	}
}

// --- Beneficiary cases & project requests ---------------------------------

// BeneficiaryCaseApprovedMsg — admin approved a beneficiary case.
func BeneficiaryCaseApprovedMsg(title string, caseID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "beneficiary_case_approved",
		RelatedEntityType: "beneficiary_cases",
		RelatedEntityID:   caseID,
		Title: LocalText{
			En:  "Beneficiary case approved",
			Ar:  "تمت الموافقة على حالة المستفيد",
			Ckb: "دۆسیەی سوودمەند پەسەند کرا",
			Kmr: "دۆسیا هەژاری هاتە قبوولکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your beneficiary case \"%s\" was approved by the admin.", title),
			Ar:  fmt.Sprintf("تمت الموافقة على حالة المستفيد \"%s\" من قِبَل المسؤول.", title),
			Ckb: fmt.Sprintf("دۆسیە سوودمەندیت «%s» لەلایەن بەڕێوەبەرەوە پەسەند کرا.", title),
			Kmr: fmt.Sprintf("دۆسیا تە یا هەژاری «%s» ژلایێ بەرپرسی ڤە هاتە قبوولکرن.", title),
		},
	}
}

// BeneficiaryCaseRejectedMsg — admin rejected a beneficiary case.
func BeneficiaryCaseRejectedMsg(title string, caseID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "beneficiary_case_rejected",
		RelatedEntityType: "beneficiary_cases",
		RelatedEntityID:   caseID,
		Title: LocalText{
			En:  "Beneficiary case rejected",
			Ar:  "تم رفض حالة المستفيد",
			Ckb: "دۆسیەی سوودمەند ڕەتکرایەوە",
			Kmr: "دۆسیا هەژاری هاتە رەتکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your beneficiary case \"%s\" was rejected. Please contact support for details.", title),
			Ar:  fmt.Sprintf("تم رفض حالة المستفيد \"%s\". يرجى التواصل مع الدعم للمزيد من التفاصيل.", title),
			Ckb: fmt.Sprintf("دۆسیە سوودمەندیت «%s» ڕەتکرایەوە. تکایە پەیوەندی بە پشتگیریەوە بکە.", title),
			Kmr: fmt.Sprintf("دۆسیا تە یا هەژاری «%s» هاتە رەتکرن. ژکەرەما خۆ دگەل پشتگیریێ پەیوەندیێ بکە.", title),
		},
	}
}

// ProjectRequestApprovedMsg — admin approved a project funding request.
func ProjectRequestApprovedMsg(title string, requestID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "project_request_approved",
		RelatedEntityType: "beneficiary_project_requests",
		RelatedEntityID:   requestID,
		Title: LocalText{
			En:  "Project request approved",
			Ar:  "تمت الموافقة على طلب المشروع",
			Ckb: "داوای پڕۆژە پەسەند کرا",
			Kmr: "داخوازا پرۆژەیێ هاتە قبوولکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your project request \"%s\" was approved by the admin. Donors can now contribute.", title),
			Ar:  fmt.Sprintf("تمت الموافقة على طلب المشروع \"%s\" من قِبَل المسؤول. يمكن للمتبرعين الآن المساهمة.", title),
			Ckb: fmt.Sprintf("داواکاری پڕۆژەکەت «%s» لەلایەن بەڕێوەبەرەوە پەسەند کرا. بەخشینکەرەکان ئێستا دەتوانن بەشداربن.", title),
			Kmr: fmt.Sprintf("داخوازا تە یا پرۆژەیێ «%s» ژلایێ بەرپرسی ڤە هاتە قبوولکرن. بەخشکار نوکە دشێن بەشدار ببن.", title),
		},
	}
}

// ProjectRequestRejectedMsg — admin rejected a project funding request.
func ProjectRequestRejectedMsg(title string, requestID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "project_request_rejected",
		RelatedEntityType: "beneficiary_project_requests",
		RelatedEntityID:   requestID,
		Title: LocalText{
			En:  "Project request rejected",
			Ar:  "تم رفض طلب المشروع",
			Ckb: "داوای پڕۆژە ڕەتکرایەوە",
			Kmr: "داخوازا پرۆژەیێ هاتە رەتکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your project request \"%s\" was rejected. Please contact support for details.", title),
			Ar:  fmt.Sprintf("تم رفض طلب المشروع \"%s\". يرجى التواصل مع الدعم للمزيد من التفاصيل.", title),
			Ckb: fmt.Sprintf("داواکاری پڕۆژەکەت «%s» ڕەتکرایەوە. تکایە پەیوەندی بە پشتگیریەوە بکە.", title),
			Kmr: fmt.Sprintf("داخوازا تە یا پرۆژەیێ «%s» هاتە رەتکرن. ژکەرەما خۆ دگەل پشتگیریێ پەیوەندیێ بکە.", title),
		},
	}
}

// ProjectRequestStatusChangedMsg — generic fallback for other transitions.
func ProjectRequestStatusChangedMsg(title, status string, requestID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "project_request_status_changed",
		RelatedEntityType: "beneficiary_project_requests",
		RelatedEntityID:   requestID,
		Title: LocalText{
			En:  "Project request updated",
			Ar:  "تم تحديث طلب المشروع",
			Ckb: "داوای پڕۆژە نوێ کرایەوە",
			Kmr: "داخوازا پرۆژەیێ هاتە نوێکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your project request \"%s\" is now %s.", title, status),
			Ar:  fmt.Sprintf("طلب المشروع \"%s\" أصبح الآن %s.", title, status),
			Ckb: fmt.Sprintf("داواکاری پڕۆژەکەت «%s» ئێستا %s ە.", title, status),
			Kmr: fmt.Sprintf("داخوازا تە یا پرۆژەیێ «%s» نوکە %s یە.", title, status),
		},
	}
}

// --- Volunteer applications + missions ------------------------------------

// VolunteerApplicationDecisionMsg — admin set application to approved /
// rejected / inactive. We bucket all 3 here with `status` interpolated since
// the layout is identical.
func VolunteerApplicationDecisionMsg(applicantName, status string, appID int64) LocalizedMessage {
	// Pick the verb per status so each language reads naturally.
	approve := status == "approved"
	reject := status == "rejected"
	enVerb := status
	arVerb := status
	ckbVerb := status
	kmrVerb := status
	switch {
	case approve:
		enVerb = "approved"; arVerb = "تمت الموافقة عليه"
		ckbVerb = "پەسەند کرا"; kmrVerb = "هاتە قبوولکرن"
	case reject:
		enVerb = "rejected"; arVerb = "تم رفضه"
		ckbVerb = "ڕەتکرایەوە"; kmrVerb = "هاتە رەتکرن"
	default: // inactive
		enVerb = "set to inactive"; arVerb = "تم تعطيله"
		ckbVerb = "ناچالاک کرا"; kmrVerb = "هاتە ناچالاککرن"
	}
	return LocalizedMessage{
		Type:              "volunteer_application_" + status,
		RelatedEntityType: "volunteer_applications",
		RelatedEntityID:   appID,
		Title: LocalText{
			En:  "Volunteer application " + status,
			Ar:  "حالة طلب التطوع",
			Ckb: "داواکاری خۆبەخشی نوێ کرایەوە",
			Kmr: "ڕەوشا داخوازا خۆبەخشیێ هاتە نوێکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("Your volunteer application for %s was %s by the admin.", applicantName, enVerb),
			Ar:  fmt.Sprintf("طلب التطوع الخاص بـ %s %s من قِبَل المسؤول.", applicantName, arVerb),
			Ckb: fmt.Sprintf("داواکاری خۆبەخشی بۆ %s لەلایەن بەڕێوەبەرەوە %s.", applicantName, ckbVerb),
			Kmr: fmt.Sprintf("داخوازا خۆبەخشیێ بۆ %s ژلایێ بەرپرسی ڤە %s.", applicantName, kmrVerb),
		},
	}
}

// MissionSignupDecisionMsg — admin acted on a mission join request. Covers
// approved / rejected / cancelled / joined (attendance) / completed / absent.
func MissionSignupDecisionMsg(missionTitle, status string, signupID int64) LocalizedMessage {
	// Tone & verb per status, then assemble.
	var (
		titleEn, titleAr, titleCkb, titleKmr string
		bodyEn, bodyAr, bodyCkb, bodyKmr     string
	)
	switch status {
	case "approved":
		titleEn = "Mission join approved"
		titleAr = "تمت الموافقة على المشاركة في المهمة"
		titleCkb = "بەشداری میسیۆن پەسەند کرا"
		titleKmr = "بەشداریا مهمەیێ هاتە قبوولکرن"
		bodyEn = fmt.Sprintf("Your request to join \"%s\" was approved. See you there!", missionTitle)
		bodyAr = fmt.Sprintf("تمت الموافقة على طلبك للمشاركة في \"%s\". نراك هناك!", missionTitle)
		bodyCkb = fmt.Sprintf("داواکاری بەشداریت بۆ «%s» پەسەند کرا. لەوێ دەتبینین!", missionTitle)
		bodyKmr = fmt.Sprintf("داخوازا تە یا بەشداریێ بۆ «%s» هاتە قبوولکرن. لێ هەڤرێ ببینین!", missionTitle)
	case "rejected":
		titleEn = "Mission join rejected"
		titleAr = "تم رفض المشاركة في المهمة"
		titleCkb = "بەشداری میسیۆن ڕەتکرایەوە"
		titleKmr = "بەشداریا مهمەیێ هاتە رەتکرن"
		bodyEn = fmt.Sprintf("Your request to join \"%s\" was rejected.", missionTitle)
		bodyAr = fmt.Sprintf("تم رفض طلبك للمشاركة في \"%s\".", missionTitle)
		bodyCkb = fmt.Sprintf("داواکاری بەشداریت بۆ «%s» ڕەتکرایەوە.", missionTitle)
		bodyKmr = fmt.Sprintf("داخوازا تە یا بەشداریێ بۆ «%s» هاتە رەتکرن.", missionTitle)
	case "cancelled":
		titleEn = "Mission join cancelled"
		titleAr = "تم إلغاء المشاركة في المهمة"
		titleCkb = "بەشداری میسیۆن هەڵوەشێنرایەوە"
		titleKmr = "بەشداریا مهمەیێ هاتە بەتالکرن"
		bodyEn = fmt.Sprintf("Your request to join \"%s\" was cancelled.", missionTitle)
		bodyAr = fmt.Sprintf("تم إلغاء طلبك للمشاركة في \"%s\".", missionTitle)
		bodyCkb = fmt.Sprintf("داواکاری بەشداریت بۆ «%s» هەڵوەشێنرایەوە.", missionTitle)
		bodyKmr = fmt.Sprintf("داخوازا تە یا بەشداریێ بۆ «%s» هاتە بەتالکرن.", missionTitle)
	case "joined":
		titleEn = "Attendance recorded"
		titleAr = "تم تسجيل الحضور"
		titleCkb = "ئامادەبوون تۆمار کرا"
		titleKmr = "ئامادەبوون هاتە تۆمارکرن"
		bodyEn = fmt.Sprintf("Your attendance for \"%s\" was recorded. Thank you!", missionTitle)
		bodyAr = fmt.Sprintf("تم تسجيل حضورك في \"%s\". شكراً لك!", missionTitle)
		bodyCkb = fmt.Sprintf("ئامادەبوونت بۆ «%s» تۆمار کرا. سوپاس!", missionTitle)
		bodyKmr = fmt.Sprintf("ئامادەبوونا تە یا «%s» هاتە تۆمارکرن. سپاس!", missionTitle)
	case "completed":
		titleEn = "Mission completed"
		titleAr = "تم إكمال المهمة"
		titleCkb = "میسیۆن تەواو کرا"
		titleKmr = "مهمە هاتە تەواوکرن"
		bodyEn = fmt.Sprintf("Your mission \"%s\" was marked complete. Thank you for volunteering!", missionTitle)
		bodyAr = fmt.Sprintf("تم وضع علامة \"مكتملة\" على مهمتك \"%s\". شكراً لتطوعك!", missionTitle)
		bodyCkb = fmt.Sprintf("میسیۆنەکەت «%s» وەک تەواوکراو دیاری کرا. سوپاس بۆ خۆبەخشیت!", missionTitle)
		bodyKmr = fmt.Sprintf("مهمەیا تە یا «%s» وەکی تەواوکری هاتە دیارکرن. سپاس بۆ خۆبەخشیا تە!", missionTitle)
	case "no_show", "absent":
		// DB uses 'no_show' (per CHECK constraint); 'absent' kept for back-compat.
		titleEn = "Marked absent"
		titleAr = "تم تسجيل الغياب"
		titleCkb = "بێئامادەبوون تۆمار کرا"
		titleKmr = "نەئامادەبوون هاتە تۆمارکرن"
		bodyEn = fmt.Sprintf("You were marked absent for \"%s\". Please contact us if this is a mistake.", missionTitle)
		bodyAr = fmt.Sprintf("تم تسجيل غيابك في \"%s\". يرجى التواصل معنا إذا كان هذا خطأ.", missionTitle)
		bodyCkb = fmt.Sprintf("وەک بێئامادە تۆمار کرایت بۆ «%s». تکایە پەیوەندیمان پێوەبکە ئەگەر ئەمە هەڵە بێت.", missionTitle)
		bodyKmr = fmt.Sprintf("وەکی نەئامادە هاتیە تۆمارکرن بۆ «%s». ژکەرەما خۆ دگەل مە پەیوەندیێ بکە ئەگەر ئەڤە چەوتیە.", missionTitle)
	case "completion_requested":
		titleEn = "Completion under review"
		titleAr = "إكمال قيد المراجعة"
		titleCkb = "تەواوکردن لە پێداچوونەوەدایە"
		titleKmr = "تەواوکرن د پشکنینێ دایە"
		bodyEn = fmt.Sprintf("You marked \"%s\" as complete; admin is reviewing it.", missionTitle)
		bodyAr = fmt.Sprintf("لقد قمت بتحديد \"%s\" كمكتملة؛ المسؤول يقوم بمراجعتها.", missionTitle)
		bodyCkb = fmt.Sprintf("«%s» ت وەک تەواوکراو دیاری کرد؛ بەڕێوەبەر پێداچوونەوەی بۆ دەکات.", missionTitle)
		bodyKmr = fmt.Sprintf("تە «%s» وەکی تەواوکری دیار کر؛ بەرپرس پشکنینێ ل سەر دکەت.", missionTitle)
	default:
		titleEn = "Mission status updated"
		titleAr = "تم تحديث حالة المهمة"
		titleCkb = "بارودۆخی میسیۆن نوێ کرایەوە"
		titleKmr = "ڕەوشا مهمەیێ هاتە نوێکرن"
		bodyEn = fmt.Sprintf("Your participation in \"%s\" is now %s.", missionTitle, status)
		bodyAr = fmt.Sprintf("مشاركتك في \"%s\" أصبحت الآن %s.", missionTitle, status)
		bodyCkb = fmt.Sprintf("بەشداریت لە «%s» ئێستا %s ە.", missionTitle, status)
		bodyKmr = fmt.Sprintf("بەشداریا تە یا «%s» نوکە %s یە.", missionTitle, status)
	}
	return LocalizedMessage{
		Type:              "volunteer_mission_" + status,
		RelatedEntityType: "volunteer_application_missions",
		RelatedEntityID:   signupID,
		Title:             LocalText{En: titleEn, Ar: titleAr, Ckb: titleCkb, Kmr: titleKmr},
		Body:              LocalText{En: bodyEn,  Ar: bodyAr,  Ckb: bodyCkb,  Kmr: bodyKmr},
	}
}

// --- Support tickets -------------------------------------------------------

// SupportTicketStatusMsg — admin moved a ticket to in_progress / resolved /
// closed. Same template for all 3 with a verb swap.
func SupportTicketStatusMsg(subject, status string, ticketID int64) LocalizedMessage {
	var titleEn, titleAr, titleCkb, titleKmr string
	var bodyEn, bodyAr, bodyCkb, bodyKmr string
	switch status {
	case "in_progress":
		titleEn = "Support request read"
		titleAr = "تمت قراءة طلب الدعم"
		titleCkb = "داواکاری پشتگیری خوێندرایەوە"
		titleKmr = "داخوازا پشتگیریێ هاتە خواندن"
		bodyEn = fmt.Sprintf("Our team is now reviewing your support request \"%s\".", subject)
		bodyAr = fmt.Sprintf("فريقنا يقوم بمراجعة طلب الدعم الخاص بك \"%s\" الآن.", subject)
		bodyCkb = fmt.Sprintf("تیمەکەمان ئێستا داواکاری پشتگیریت «%s» دەخوێنێتەوە.", subject)
		bodyKmr = fmt.Sprintf("تیمێ مە نوکە داخوازا تە یا پشتگیریێ «%s» دخوینیت.", subject)
	case "resolved":
		titleEn = "Support request resolved"
		titleAr = "تم حل طلب الدعم"
		titleCkb = "داواکاری پشتگیری چارەسەر کرا"
		titleKmr = "داخوازا پشتگیریێ هاتە چارەسەرکرن"
		bodyEn = fmt.Sprintf("Your support request \"%s\" was marked as resolved. Reply if you need more help.", subject)
		bodyAr = fmt.Sprintf("تم وضع علامة \"تم الحل\" على طلب الدعم \"%s\". قم بالرد إذا احتجت إلى مزيد من المساعدة.", subject)
		bodyCkb = fmt.Sprintf("داواکاری پشتگیریت «%s» وەک چارەسەرکراو دیاری کرا. وەڵام بدەوە ئەگەر یارمەتی زیاترت پێویستە.", subject)
		bodyKmr = fmt.Sprintf("داخوازا تە یا پشتگیریێ «%s» وەکی چارەسەرکری هاتە دیارکرن. ڤەگەرینێ بدە ئەگەر ئاریکاریا تە یا زێدەتر پێدڤی بیت.", subject)
	case "closed":
		titleEn = "Support request closed"
		titleAr = "تم إغلاق طلب الدعم"
		titleCkb = "داواکاری پشتگیری داخرا"
		titleKmr = "داخوازا پشتگیریێ هاتە داخستن"
		bodyEn = fmt.Sprintf("Your support request \"%s\" was closed. Open a new request anytime.", subject)
		bodyAr = fmt.Sprintf("تم إغلاق طلب الدعم \"%s\". يمكنك فتح طلب جديد في أي وقت.", subject)
		bodyCkb = fmt.Sprintf("داواکاری پشتگیریت «%s» داخرا. هەر کاتێک بتەوێت داواکارییەکی نوێ بکەرەوە.", subject)
		bodyKmr = fmt.Sprintf("داخوازا تە یا پشتگیریێ «%s» هاتە داخستن. دەمێ بشێی داخوازەکا نوو ڤەکە.", subject)
	default:
		titleEn = "Support request updated"
		titleAr = "تم تحديث طلب الدعم"
		titleCkb = "داواکاری پشتگیری نوێ کرایەوە"
		titleKmr = "داخوازا پشتگیریێ هاتە نوێکرن"
		bodyEn = fmt.Sprintf("Your support request \"%s\" is now %s.", subject, status)
		bodyAr = fmt.Sprintf("طلب الدعم \"%s\" أصبح الآن %s.", subject, status)
		bodyCkb = fmt.Sprintf("داواکاری پشتگیریت «%s» ئێستا %s ە.", subject, status)
		bodyKmr = fmt.Sprintf("داخوازا تە یا پشتگیریێ «%s» نوکە %s یە.", subject, status)
	}
	return LocalizedMessage{
		Type:              "support_ticket_" + status,
		RelatedEntityType: "support_tickets",
		RelatedEntityID:   ticketID,
		Title:             LocalText{En: titleEn, Ar: titleAr, Ckb: titleCkb, Kmr: titleKmr},
		Body:              LocalText{En: bodyEn,  Ar: bodyAr,  Ckb: bodyCkb,  Kmr: bodyKmr},
	}
}

// ============================================================================
// BROADCAST TEMPLATES — fanned to all users of a role (or everyone) by
// Notifier.Broadcast(). Use these when the content isn't tied to a single
// user (e.g. "a new partner just joined").
// ============================================================================

// NewVolunteerMissionMsg — broadcast to role_id=3 when admin creates a mission.
func NewVolunteerMissionMsg(missionTitle, city, dateText string, missionID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "new_volunteer_mission",
		RelatedEntityType: "volunteer_missions",
		RelatedEntityID:   missionID,
		Title: LocalText{
			En:  "New volunteer mission",
			Ar:  "مهمة تطوعية جديدة",
			Ckb: "میسیۆنێکی خۆبەخشی نوێ",
			Kmr: "مهمەکا خۆبەخشیێ یا نوو",
		},
		Body: LocalText{
			En:  fmt.Sprintf("A new volunteer mission is available: %s. %s · %s.", missionTitle, city, dateText),
			Ar:  fmt.Sprintf("تتوفر مهمة تطوعية جديدة: %s. %s · %s.", missionTitle, city, dateText),
			Ckb: fmt.Sprintf("میسیۆنێکی خۆبەخشی نوێ بەردەستە: %s. %s · %s.", missionTitle, city, dateText),
			Kmr: fmt.Sprintf("مهمەکا خۆبەخشیێ یا نوو بەردەست ە: %s. %s · %s.", missionTitle, city, dateText),
		},
	}
}

// NewPartnerMsg — broadcast to everyone when admin adds a partner org.
func NewPartnerMsg(partnerName string, partnerID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "new_partner",
		RelatedEntityType: "partners",
		RelatedEntityID:   partnerID,
		Title: LocalText{
			En:  "New partner added",
			Ar:  "تم إضافة شريك جديد",
			Ckb: "هاوبەشێکی نوێ زیاد کرا",
			Kmr: "هەڤپشکێکێ نوو هاتە زێدەکرن",
		},
		Body: LocalText{
			En:  fmt.Sprintf("A new partner was added: %s.", partnerName),
			Ar:  fmt.Sprintf("تم إضافة شريك جديد: %s.", partnerName),
			Ckb: fmt.Sprintf("هاوبەشێکی نوێ زیاد کرا: %s.", partnerName),
			Kmr: fmt.Sprintf("هەڤپشکێکێ نوو هاتە زێدەکرن: %s.", partnerName),
		},
	}
}

// NewMediaPostMsg — broadcast to everyone when admin publishes a news /
// activity / media post.
func NewMediaPostMsg(postTitle string, postID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "new_media_post",
		RelatedEntityType: "media_posts",
		RelatedEntityID:   postID,
		Title: LocalText{
			En:  "New post in news and activities",
			Ar:  "منشور جديد في الأخبار والأنشطة",
			Ckb: "پۆستێکی نوێ لە هەواڵ و چالاکیەکان",
			Kmr: "پۆستەکا نوو د هەڤالان و چالاکیان دە",
		},
		Body: LocalText{
			En:  fmt.Sprintf("A new post is available: %s.", postTitle),
			Ar:  fmt.Sprintf("منشور جديد متاح: %s.", postTitle),
			Ckb: fmt.Sprintf("پۆستێکی نوێ بەردەستە: %s.", postTitle),
			Kmr: fmt.Sprintf("پۆستەکا نوو بەردەست ە: %s.", postTitle),
		},
	}
}

// NewCampaignMsg — broadcast to everyone when a new fundraising campaign is
// published, so donors can discover and support it. (New content parity with
// NewMediaPostMsg / NewPartnerMsg.)
func NewCampaignMsg(campaignTitle string, campaignID int64) LocalizedMessage {
	return LocalizedMessage{
		Type:              "new_campaign",
		RelatedEntityType: "campaigns",
		RelatedEntityID:   campaignID,
		Title: LocalText{
			En:  "New campaign to support",
			Ar:  "حملة جديدة للدعم",
			Ckb: "کەمپینێکی نوێ بۆ پشتگیری",
			Kmr: "کامپانیایەکا نوو بۆ پشتگیریێ",
		},
		Body: LocalText{
			En:  fmt.Sprintf("A new campaign is live: %s.", campaignTitle),
			Ar:  fmt.Sprintf("حملة جديدة متاحة: %s.", campaignTitle),
			Ckb: fmt.Sprintf("کەمپینێکی نوێ بەردەستە: %s.", campaignTitle),
			Kmr: fmt.Sprintf("کامپانیایەکا نوو بەردەست ە: %s.", campaignTitle),
		},
	}
}

// ===== Donor ↔ campaign-owner chat (Phase 28) =====

// ChatRequestMsg notifies the recipient that someone wants to start a chat.
// Type "chat_request" + related_entity_id=threadID drives the Accept/Decline
// action in the mobile Alerts tab.
func ChatRequestMsg(requesterName, campaignName string, threadID int64) LocalizedMessage {
	who := requesterName
	if who == "" {
		who = "Someone"
	}
	return LocalizedMessage{
		Type:              "chat_request",
		RelatedEntityType: "chat_thread",
		RelatedEntityID:   threadID,
		Title: LocalText{
			En:  "New chat request",
			Ar:  "طلب محادثة جديد",
			Ckb: "داواکاری گفتوگۆی نوێ",
			Kmr: "داخوازا axaftinê ya nû",
		},
		Body: LocalText{
			En:  fmt.Sprintf("%s wants to chat with you about \"%s\". Open Alerts to accept.", who, campaignName),
			Ar:  fmt.Sprintf("يريد %s التحدث معك بخصوص \"%s\". افتح الإشعارات للقبول.", who, campaignName),
			Ckb: fmt.Sprintf("%s دەیەوێت لەگەڵت گفتوگۆ بکات دەربارەی «%s». ئاگاداریەکان بکەرەوە بۆ پەسەندکردن.", who, campaignName),
			Kmr: fmt.Sprintf("%s دخوازیت ب تە re biaxive derbarê \"%s\". Hişyariyan veke ji bo qebûlkirinê.", who, campaignName),
		},
	}
}

// ChatAcceptedMsg notifies the initiator that the recipient accepted.
func ChatAcceptedMsg(accepterName string, threadID int64) LocalizedMessage {
	who := accepterName
	if who == "" {
		who = "Your contact"
	}
	return LocalizedMessage{
		Type:              "chat_accepted",
		RelatedEntityType: "chat_thread",
		RelatedEntityID:   threadID,
		Title: LocalText{
			En:  "Chat request accepted",
			Ar:  "تم قبول طلب المحادثة",
			Ckb: "داواکاری گفتوگۆ پەسەند کرا",
			Kmr: "Daxwaza axaftinê hat qebûlkirin",
		},
		Body: LocalText{
			En:  fmt.Sprintf("%s accepted your chat request. You can now message each other.", who),
			Ar:  fmt.Sprintf("قبل %s طلب المحادثة. يمكنكما الآن تبادل الرسائل.", who),
			Ckb: fmt.Sprintf("%s داواکاری گفتوگۆکەت پەسەند کرد. ئێستا دەتوانن نامە بنێرن.", who),
			Kmr: fmt.Sprintf("%s daxwaza te ya axaftinê qebûl kir. Niha hûn dikarin ji hev re binivîsin.", who),
		},
	}
}

// ChatNewMessageMsg notifies the other party of a new chat message.
func ChatNewMessageMsg(senderName, preview string, threadID int64) LocalizedMessage {
	who := senderName
	if who == "" {
		who = "New message"
	}
	return LocalizedMessage{
		Type:              "chat_message",
		RelatedEntityType: "chat_thread",
		RelatedEntityID:   threadID,
		Title: LocalText{
			En:  fmt.Sprintf("Message from %s", who),
			Ar:  fmt.Sprintf("رسالة من %s", who),
			Ckb: fmt.Sprintf("نامە لە %s", who),
			Kmr: fmt.Sprintf("Peyam ji %s", who),
		},
		Body: LocalText{
			En:  preview,
			Ar:  preview,
			Ckb: preview,
			Kmr: preview,
		},
	}
}
