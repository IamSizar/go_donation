package handlers

import "strings"

// maxCityPhotos is how many photos one suggested place may carry. The app's
// picker stops at the same number; this is the server's own ceiling.
const maxCityPhotos = 6

// cleanCityPhotos keeps only the photo paths POST /api/uploads could have
// issued: the relative local form ("images/uploads/<name>") or an https URL
// containing "/uploads/" (the R2 public bucket). Anything else — a data: URI, a
// file:// path, a link to someone else's server, markup — is dropped, so the
// public City Guide never renders a URL a stranger chose. Duplicates and
// anything past maxCityPhotos are dropped too. Order is kept.
//
// Dropping rather than rejecting is deliberate: the place itself is a valid
// suggestion, and a bad photo should cost the photo, not the submission.
func cleanCityPhotos(in []string) []string {
	out := make([]string, 0, len(in))
	seen := map[string]bool{}
	for _, raw := range in {
		p := strings.TrimSpace(raw)
		if p == "" || len(p) > 500 || seen[p] {
			continue
		}
		if strings.ContainsAny(p, " \\\t\r\n<>\"'") || strings.Contains(p, "..") {
			continue
		}
		local := strings.HasPrefix(p, "images/uploads/")
		remote := strings.HasPrefix(p, "https://") && strings.Contains(p, "/uploads/")
		if !local && !remote {
			continue
		}
		seen[p] = true
		out = append(out, p)
		if len(out) == maxCityPhotos {
			break
		}
	}
	return out
}
