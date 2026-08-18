package handlers

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/storage"
)

// Uploads are validated by extension alone — the bytes are never inspected.
// That was a defensible trade while these files were served from our own
// /images route as static content. It stopped being defensible when uploads
// moved to the R2 public bucket domain: an SVG is XML that can carry <script>,
// so a stored .svg became a script-capable document on a public origin,
// reachable by anyone holding the URL with no authentication in front of it.
//
// Nothing in either client uploads or renders an SVG (checked across admin-web
// and the Flutter app), so the format is removed rather than sanitised. That
// closes the hole completely instead of relying on a sanitiser staying correct.
//
// The wider gap — an extension that lies about its content — is NOT closed by
// this change and is deliberately left visible in the test below.

// uploadRequest builds a multipart POST carrying one file.
func uploadRequest(t *testing.T, filename string, content []byte) *http.Request {
	t.Helper()
	body := new(bytes.Buffer)
	w := multipart.NewWriter(body)
	part, err := w.CreateFormFile("file", filename)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write(content); err != nil {
		t.Fatal(err)
	}
	w.Close()

	req := httptest.NewRequest(http.MethodPost, "/api/admin/uploads", body)
	req.Header.Set("Content-Type", w.FormDataContentType())
	return req
}

// doUpload runs one upload against a handler backed by a temp directory.
func doUpload(t *testing.T, filename string, content []byte) *httptest.ResponseRecorder {
	t.Helper()
	gin.SetMode(gin.TestMode)
	h := NewAdminUploadHandler(storage.NewLocal(t.TempDir()))

	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = uploadRequest(t, filename, content)
	h.Upload(c)
	return rec
}

func TestUploadRejectsSVG(t *testing.T) {
	svg := []byte(`<svg xmlns="http://www.w3.org/2000/svg">` +
		`<script>alert(document.domain)</script></svg>`)
	rec := doUpload(t, "payload.svg", svg)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status %d, want 400 — an SVG must not be storable", rec.Code)
	}
	// The message must not advertise a format we refuse, or an operator will
	// keep trying and believe the upload is broken.
	if strings.Contains(strings.ToLower(rec.Body.String()), "svg") {
		t.Errorf("the error still offers svg: %s", rec.Body.String())
	}
}

func TestUploadAcceptsTheFormatsInUse(t *testing.T) {
	// A minimal but genuine PNG header, so this is not merely an extension test.
	png := []byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}
	for _, name := range []string{"a.png", "b.jpg", "c.jpeg", "d.gif", "e.webp", "f.pdf"} {
		t.Run(name, func(t *testing.T) {
			rec := doUpload(t, name, png)
			if rec.Code != http.StatusOK {
				t.Fatalf("status %d for %s, want 200: %s", rec.Code, name, rec.Body.String())
			}
			var body map[string]any
			if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
				t.Fatalf("response is not JSON: %v", err)
			}
			if _, ok := body["path"]; !ok {
				t.Errorf("no stored path returned: %s", rec.Body.String())
			}
		})
	}
}

func TestUploadRejectsUnknownExtensions(t *testing.T) {
	for _, name := range []string{"x.html", "x.js", "x.exe", "x.php", "noextension"} {
		t.Run(name, func(t *testing.T) {
			if rec := doUpload(t, name, []byte("whatever")); rec.Code != http.StatusBadRequest {
				t.Errorf("status %d for %s, want 400", rec.Code, name)
			}
		})
	}
}

// Documents a gap that this change does NOT close, so nobody reads the tests
// above and concludes uploads are content-verified. Validation is by extension
// only: a file whose bytes are HTML but whose name ends in .png is accepted.
// It is far less dangerous than the SVG case — the object is served with an
// image content type and X-Content-Type-Options prevents sniffing — but it is
// real, and closing it means magic-byte checks (recorded in OPOS 21738).
func TestUploadStillTrustsTheExtensionOverTheBytes(t *testing.T) {
	html := []byte("<html><script>alert(1)</script></html>")
	rec := doUpload(t, "actually-html.png", html)
	if rec.Code != http.StatusOK {
		t.Skip("uploads now verify content; delete this test and close the gap in 21738")
	}
	t.Log("known gap: content is not sniffed; the extension is trusted")
}
