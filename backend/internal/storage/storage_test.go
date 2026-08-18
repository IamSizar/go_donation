package storage

import (
	"errors"
	"testing"
)

// TestSanitizeKeyRejectsTraversal pins the guard that keeps an uploaded
// filename from choosing where it lands.
//
// Two of the four upload paths build their key from filepath.Ext of a filename
// the client supplied. On local disk the key is joined onto UPLOAD_DIR before
// the file is opened for writing, so a key with a parent-directory segment
// writes outside the upload root; on R2 it creates objects at a path no
// cleanup routine expects. There is no legitimate upload whose name needs
// "..", so every spelling of it is refused rather than repaired.
func TestSanitizeKeyRejectsTraversal(t *testing.T) {
	for _, bad := range []string{
		"../secrets.env",
		"uploads/../../etc/passwd",
		"..",
		"uploads/..",
		"a/../..",
		"..\\..\\windows",
		"",
		"   ",
		"/",
		"///",
	} {
		if got, err := SanitizeKey(bad); !errors.Is(err, ErrUnsafeKey) {
			t.Errorf("SanitizeKey(%q) = (%q, %v); want ErrUnsafeKey", bad, got, err)
		}
	}
}

// TestSanitizeKeyCanonicalises pins that two spellings of one key cannot
// become two objects, and that the keys the four real call sites actually
// build pass through untouched.
//
// The backslash case is the non-obvious one: object keys are URL paths, not
// filesystem paths, so a Windows-style separator arriving inside a client's
// filename would otherwise be a literal character in the key on R2 and a
// directory separator on local disk — the same upload landing in two different
// places depending on which backend is live.
func TestSanitizeKeyCanonicalises(t *testing.T) {
	cases := map[string]string{
		// The keys the handlers really produce, which must survive verbatim.
		"uploads/ab12cd34.png":     "uploads/ab12cd34.png",
		"profile_7_1771234567.jpg": "profile_7_1771234567.jpg",
		"idcard_42_1771234567.jpg": "idcard_42_1771234567.jpg",
		// Canonicalisation.
		"/uploads/x.png":       "uploads/x.png",
		"///uploads/x.png":     "uploads/x.png",
		"uploads//x.png":       "uploads/x.png",
		"uploads/./x.png":      "uploads/x.png",
		"uploads\\x.png":       "uploads/x.png",
		"  uploads/x.png  ":    "uploads/x.png",
		"uploads/sub/../x.png": "uploads/x.png",
	}
	for in, want := range cases {
		got, err := SanitizeKey(in)
		if err != nil {
			t.Errorf("SanitizeKey(%q) errored: %v", in, err)
			continue
		}
		if got != want {
			t.Errorf("SanitizeKey(%q) = %q, want %q", in, got, want)
		}
	}
}

// TestJoinPublicURL pins the URL construction, which is where this migration
// is most likely to go quietly wrong: its output is written into a database
// column permanently, so a joining bug is not a failed request, it is a corrupt
// row that outlives the fix.
//
// The double-slash cases are the real ones. A trailing slash on
// R2_PUBLIC_BASE_URL and a leading slash on a key are each harmless alone;
// together they name an object whose key begins with an empty segment, which
// does not exist in the bucket. The path-prefix case is included because a
// custom domain may serve the bucket from a subpath, and truncating that would
// point every URL at the domain root.
func TestJoinPublicURL(t *testing.T) {
	cases := []struct{ base, key, want string }{
		{"https://media.example.org", "uploads/x.png", "https://media.example.org/uploads/x.png"},
		{"https://media.example.org/", "uploads/x.png", "https://media.example.org/uploads/x.png"},
		{"https://media.example.org///", "/uploads/x.png", "https://media.example.org/uploads/x.png"},
		{"https://media.example.org", "/uploads/x.png", "https://media.example.org/uploads/x.png"},
		{"https://example.org/media", "profile_7_1.jpg", "https://example.org/media/profile_7_1.jpg"},
		{"  https://media.example.org  ", "  uploads/x.png  ", "https://media.example.org/uploads/x.png"},
	}
	for _, c := range cases {
		if got := JoinPublicURL(c.base, c.key); got != c.want {
			t.Errorf("JoinPublicURL(%q, %q) = %q, want %q", c.base, c.key, got, c.want)
		}
	}
}

// TestJoinPublicURLOutputIsRecognisedAsAbsolute closes the loop between the
// two halves of the coexistence rule.
//
// Legacy rows hold relative paths and new rows hold absolute URLs in the SAME
// column, and everything downstream distinguishes them by asking whether the
// string starts with http(s)://. This asserts that what the R2 backend
// produces actually answers yes to that question, and — more usefully — that
// what the local backend produces answers no. If those two ever agreed, one of
// the two shapes would silently stop resolving.
func TestJoinPublicURLOutputIsRecognisedAsAbsolute(t *testing.T) {
	r2URL := JoinPublicURL("https://media.example.org", "uploads/x.png")
	if !IsAbsoluteURL(r2URL) {
		t.Errorf("an R2 URL must be recognised as absolute so clients pass it through unchanged; got %q", r2URL)
	}

	for _, legacy := range []string{
		"images/uploads/ab12.png",
		"images/profile_7_1771234567.jpg",
		"images/seed/foo.png",
	} {
		if IsAbsoluteURL(legacy) {
			t.Errorf("a legacy relative path must NOT be treated as absolute, or clients would stop prefixing the API origin onto it; got %q", legacy)
		}
	}
}

// TestIsAbsoluteURL pins the exact test both clients apply, including its
// case-insensitivity and its rejection of near-misses.
//
// The scheme-relative "//host/x.png" case is the interesting one: it is a
// valid URL to a browser and meaningless to Flutter's Image.network against an
// API origin, so it must never be produced. It is listed here as NOT absolute
// to record that this backend does not consider it a legitimate stored shape.
func TestIsAbsoluteURL(t *testing.T) {
	absolute := []string{
		"https://media.example.org/uploads/x.png",
		"http://media.example.org/uploads/x.png",
		"HTTPS://MEDIA.EXAMPLE.ORG/x.png",
		"  https://media.example.org/x.png  ",
	}
	for _, s := range absolute {
		if !IsAbsoluteURL(s) {
			t.Errorf("IsAbsoluteURL(%q) = false, want true", s)
		}
	}

	relative := []string{
		"images/uploads/x.png",
		"/images/uploads/x.png",
		"//media.example.org/x.png",
		"media.example.org/x.png",
		"",
	}
	for _, s := range relative {
		if IsAbsoluteURL(s) {
			t.Errorf("IsAbsoluteURL(%q) = true, want false", s)
		}
	}
}

// TestContentTypeForKey pins the types stored on R2 objects.
//
// This did not matter before and matters now. A file on local disk is typed by
// Gin at response time from its filename; an object in a bucket carries the
// Content-Type it was stored with, forever. Store a JPEG untyped and R2 serves
// application/octet-stream, at which point a browser downloads a profile photo
// instead of drawing it — and fixing it later means re-uploading every object,
// not changing a line of code. The registration and profile paths never
// computed a MIME type at all, so this function is the only thing standing
// between them and a bucket full of untyped bytes.
//
// The table is asserted explicitly rather than delegated to
// mime.TypeByExtension because that function reads the host's /etc/mime.types
// and can answer differently on a developer's Mac and in the Alpine container.
// A stored Content-Type that depends on which machine ran the upload is a bug
// waiting for a confusing afternoon.
func TestContentTypeForKey(t *testing.T) {
	cases := map[string]string{
		"uploads/x.png":            "image/png",
		"uploads/x.jpg":            "image/jpeg",
		"uploads/x.jpeg":           "image/jpeg",
		"uploads/x.JPG":            "image/jpeg",
		"uploads/x.gif":            "image/gif",
		"uploads/x.webp":           "image/webp",
		"uploads/x.svg":            "image/svg+xml",
		"uploads/x.pdf":            "application/pdf",
		"profile_7_1771234567.jpg": "image/jpeg",
	}
	for key, want := range cases {
		if got := ContentTypeForKey(key); got != want {
			t.Errorf("ContentTypeForKey(%q) = %q, want %q", key, got, want)
		}
	}

	// An unidentifiable extension must fall back to octet-stream rather than
	// guess. Being honest about unknown bytes is correct; guessing "image/png"
	// at a file that is not one would be worse than no answer.
	if got := ContentTypeForKey("uploads/x.wat"); got != "application/octet-stream" {
		t.Errorf("unknown extension must fall back to application/octet-stream, got %q", got)
	}
	if got := ContentTypeForKey("uploads/noextension"); got != "application/octet-stream" {
		t.Errorf("a key with no extension must fall back to application/octet-stream, got %q", got)
	}
}
