package handlers

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The allowlist is the whole security story for the remote branch: the stored
// path is attacker-influenced, so anything not underneath the configured public
// base must be refused before a request leaves the process.
func TestMediaDownloadRefusesURLsOutsideTheMediaBase(t *testing.T) {
	const base = "https://pub-abc123.r2.dev"
	h := NewMediaDownloadHandler(base, t.TempDir())

	refused := []string{
		"https://evil.test/secret.jpg",
		// Prefix look-alikes: same leading characters, different host.
		"https://pub-abc123.r2.dev.evil.test/x.jpg",
		"https://pub-abc123.r2.devil/x.jpg",
		// Classic SSRF targets.
		"http://169.254.169.254/latest/meta-data/",
		"http://localhost:8080/api/admin/users",
		"http://127.0.0.1/",
	}
	for _, stored := range refused {
		t.Run(stored, func(t *testing.T) {
			body, _, err := h.open(context.Background(), stored)
			if err == nil {
				body.Close()
				t.Fatalf("relayed %q; it must be refused", stored)
			}
		})
	}
}

// A URL genuinely under the base is relayed, with the object store's own
// content type preserved.
func TestMediaDownloadRelaysObjectsUnderTheBase(t *testing.T) {
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/jpeg")
		io.WriteString(w, "jpeg-bytes")
	}))
	defer origin.Close()

	h := NewMediaDownloadHandler(origin.URL, t.TempDir())
	body, ct, err := h.open(context.Background(), origin.URL+"/uploads/photo.jpg")
	if err != nil {
		t.Fatalf("refused a legitimate object: %v", err)
	}
	defer body.Close()
	got, _ := io.ReadAll(body)
	if string(got) != "jpeg-bytes" {
		t.Errorf("relayed %q, want the object's bytes", got)
	}
	if ct != "image/jpeg" {
		t.Errorf("content type %q, want image/jpeg", ct)
	}
}

// With no R2 configured, the remote branch is closed entirely rather than
// falling back to fetching whatever it was handed.
func TestMediaDownloadRefusesRemoteWhenNoBaseConfigured(t *testing.T) {
	h := NewMediaDownloadHandler("", t.TempDir())
	if body, _, err := h.open(context.Background(), "https://pub-abc.r2.dev/x.jpg"); err == nil {
		body.Close()
		t.Fatal("relayed a remote object with no configured base")
	}
}

// Legacy relative paths resolve inside the upload directory — and only there.
func TestMediaDownloadLegacyPathsCannotEscapeUploadDir(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "ok.jpg"), []byte("local"), 0o600); err != nil {
		t.Fatal(err)
	}
	// A secret sitting beside the upload directory, as one would in a real
	// deployment's parent folder.
	secret := filepath.Join(filepath.Dir(dir), "secret.env")
	if err := os.WriteFile(secret, []byte("DB_PASSWORD=hunter2"), 0o600); err != nil {
		t.Fatal(err)
	}
	defer os.Remove(secret)

	h := NewMediaDownloadHandler("", dir)

	t.Run("resolves a real file", func(t *testing.T) {
		body, ct, err := h.open(context.Background(), "images/ok.jpg")
		if err != nil {
			t.Fatalf("could not open a legitimate legacy file: %v", err)
		}
		defer body.Close()
		got, _ := io.ReadAll(body)
		if string(got) != "local" {
			t.Errorf("got %q, want the file's bytes", got)
		}
		if ct != "image/jpeg" {
			t.Errorf("content type %q, want image/jpeg", ct)
		}
	})

	for _, escape := range []string{
		"images/../../secret.env",
		"../secret.env",
		"images/../../../etc/passwd",
		"/etc/passwd",
	} {
		t.Run("refuses "+escape, func(t *testing.T) {
			body, _, err := h.open(context.Background(), escape)
			if err == nil {
				got, _ := io.ReadAll(body)
				body.Close()
				t.Fatalf("escaped the upload directory and read %q", got)
			}
		})
	}
}

// The filename ends up inside a response header, so anything that could break
// out of the quoted string must be stripped.
func TestDownloadFilenameIsHeaderSafe(t *testing.T) {
	cases := map[string]string{
		"https://pub-abc.r2.dev/uploads/814f23bd.jpg": "814f23bd.jpg",
		"images/uploads/photo.png":                    "photo.png",
		"https://pub-abc.r2.dev/a.jpg?v=2":            "a.jpg",
		`weird/"quoted".jpg`:                          "quoted.jpg",
		"images/":                                     "download",
		"":                                            "download",
	}
	for stored, want := range cases {
		if got := downloadFilename(stored); got != want {
			t.Errorf("downloadFilename(%q) = %q, want %q", stored, got, want)
		}
	}
	// No result may contain a character that could terminate or split the
	// Content-Disposition header.
	for _, stored := range []string{"a\"b.jpg", "a\r\nX-Evil: 1.jpg", "a\\b.jpg"} {
		got := downloadFilename(stored)
		if strings.ContainsAny(got, "\"\\\r\n") {
			t.Errorf("downloadFilename(%q) = %q, which is not header-safe", stored, got)
		}
	}
}
