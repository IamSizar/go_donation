package notify

import (
	"strings"
	"testing"
)

// A general donation has no campaign. The donor's phone showed
// «للحملة "general donation". 0 من أصل 0 IQD» — a raw English placeholder and a
// meaningless 0-of-0 progress line. With no campaign the message says only
// what is true.
func TestDonationMessagesWithoutCampaignQuoteNoCampaign(t *testing.T) {
	msgs := map[string]LocalizedMessage{
		"approved":  DonationApprovedMsg("5,000", "IQD", "", "0", "0", 1),
		"rejected":  DonationRejectedMsg("5,000", "IQD", "", 1),
		"confirmed": DonationPaymentConfirmedMsg("5,000", "IQD", "", 1),
		"cancelled": DonationCancelledByDonorMsg("5,000", "IQD", "", 1),
	}
	for name, m := range msgs {
		for lang, body := range map[string]string{"en": m.Body.En, "ar": m.Body.Ar} {
			if strings.Contains(body, "general donation") || strings.Contains(body, "\"\"") || strings.Contains(body, "0 من أصل") || strings.Contains(body, "of 0") {
				t.Errorf("%s/%s: body still quotes a campaign or a 0 goal: %q", name, lang, body)
			}
			if !strings.Contains(body, "5,000") {
				t.Errorf("%s/%s: amount missing: %q", name, lang, body)
			}
		}
	}
}
