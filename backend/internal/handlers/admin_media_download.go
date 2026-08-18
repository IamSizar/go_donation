// Package handlers — downloading a stored media file as a file.
//
// WHY A SERVER ENDPOINT, when the photo already has a public URL the browser
// can reach on its own:
//
// Objects are served from the R2 public bucket domain, which is a different
// origin from the dashboard and sends no Access-Control-Allow-Origin header.
// That closes both of the purely client-side routes to a download:
//
//   - fetch() into a Blob is refused by CORS.
//   - <a download href="https://pub-….r2.dev/…"> does NOT download. The
//     download attribute is ignored for cross-origin URLs, so the browser
//     navigates instead, and because the object is served as image/jpeg the
//     photo simply opens in a bare tab — the exact dead end PhotoViewer was
//     written to get rid of.
//   - Drawing the image to a canvas and exporting it fails too: a cross-origin
//     image taints the canvas and toDataURL throws.
//
// So the bytes have to come back through an origin that can set its own
// headers. This handler re-fetches the object server-side, where the
// same-origin policy does not apply, and returns it with Content-Disposition:
// attachment so the browser saves it under a sensible name.
//
// SSRF: the path is attacker-controllable, so it is never treated as a URL to
// fetch. It must either match the configured public media base exactly by
// prefix, or be a relative legacy path resolved inside the upload directory.
// Anything else is refused before a single byte leaves the process.
package handlers

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// mediaDownloadTimeout bounds the server-side re-fetch. Generous for a photo
// over a slow link, short enough that a hung object store cannot pin a request
// goroutine indefinitely.
const mediaDownloadTimeout = 30 * time.Second

// maxMediaDownloadBytes caps what we will relay. Uploads are already limited
// well below this; the cap exists so a mistake elsewhere cannot turn this
// endpoint into an unbounded egress pipe.
const maxMediaDownloadBytes = 32 << 20 // 32 MB

// MediaDownloadHandler serves stored media as a downloadable file.
type MediaDownloadHandler struct {
	// publicBase is the configured R2 public base URL ("" when uploads are
	// local). Only objects underneath it may be relayed.
	publicBase string
	// uploadDir backs legacy relative paths still served at /images.
	uploadDir string
	client    *http.Client
}

// NewMediaDownloadHandler builds the handler. publicBase should be the same
// R2_PUBLIC_BASE_URL the storage layer was configured with; pass "" when
// uploads are local, which disables the remote branch entirely.
func NewMediaDownloadHandler(publicBase, uploadDir string) *MediaDownloadHandler {
	return &MediaDownloadHandler{
		publicBase: strings.TrimRight(strings.TrimSpace(publicBase), "/"),
		uploadDir:  uploadDir,
		client:     &http.Client{Timeout: mediaDownloadTimeout},
	}
}

// Download streams the media file named by the ?path= query parameter with a
// Content-Disposition that makes the browser save it.
//
// GET /api/admin/media/download?path=<stored path>
//
// The path is whatever was stored on the row — an absolute R2 URL for anything
// uploaded since the R2 cutover, or a relative "images/…" path for older rows.
// Both are accepted; anything pointing elsewhere is rejected as a bad request.
func (h *MediaDownloadHandler) Download(c *gin.Context) {
	raw := strings.TrimSpace(c.Query("path"))
	if raw == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false,
			"error": "A file path is required."})
		return
	}

	body, contentType, err := h.open(c.Request.Context(), raw)
	if err != nil {
		// The reason is logged, never returned: it can name internal paths.
		fmt.Fprintf(os.Stderr, "[media-download] refused %q: %v\n", raw, err)
		c.JSON(http.StatusBadRequest, gin.H{"success": false,
			"error": "That file could not be downloaded."})
		return
	}
	defer body.Close()

	// A quoted ASCII filename plus RFC 5987 filename* so non-ASCII names
	// survive; browsers prefer filename* when they understand it.
	name := downloadFilename(raw)
	c.Header("Content-Disposition", fmt.Sprintf(
		"attachment; filename=%q; filename*=UTF-8''%s", name, url.PathEscape(name)))
	c.Header("X-Content-Type-Options", "nosniff")
	c.Status(http.StatusOK)
	c.Writer.Header().Set("Content-Type", contentType)
	if _, err := io.Copy(c.Writer, io.LimitReader(body, maxMediaDownloadBytes)); err != nil {
		// Headers are already sent, so there is no clean way to report this;
		// the truncated response is the signal. Log it for support.
		fmt.Fprintf(os.Stderr, "[media-download] relay interrupted for %q: %v\n", raw, err)
	}
}

// open resolves a stored path to a byte stream and a content type, refusing
// anything that does not belong to this deployment's own media.
func (h *MediaDownloadHandler) open(ctx context.Context, stored string) (io.ReadCloser, string, error) {
	if strings.HasPrefix(stored, "http://") || strings.HasPrefix(stored, "https://") {
		return h.openRemote(ctx, stored)
	}
	return h.openLocal(stored)
}

// openRemote relays an object from the configured public media base.
func (h *MediaDownloadHandler) openRemote(ctx context.Context, stored string) (io.ReadCloser, string, error) {
	if h.publicBase == "" {
		return nil, "", fmt.Errorf("no public media base configured")
	}
	// Prefix match with a boundary check, so a look-alike host such as
	// "https://pub-….r2.dev.evil.test/x" cannot pass by sharing a prefix.
	if stored != h.publicBase && !strings.HasPrefix(stored, h.publicBase+"/") {
		return nil, "", fmt.Errorf("outside the configured media base")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, stored, nil)
	if err != nil {
		return nil, "", err
	}
	res, err := h.client.Do(req)
	if err != nil {
		return nil, "", err
	}
	if res.StatusCode != http.StatusOK {
		res.Body.Close()
		return nil, "", fmt.Errorf("object store returned %d", res.StatusCode)
	}
	ct := res.Header.Get("Content-Type")
	if ct == "" {
		ct = "application/octet-stream"
	}
	return res.Body, ct, nil
}

// openLocal resolves a legacy relative path inside the upload directory.
func (h *MediaDownloadHandler) openLocal(stored string) (io.ReadCloser, string, error) {
	// Strip the public "/images" route prefix the stored value carries, then
	// resolve inside uploadDir. Cleaning before joining defeats "../" escapes,
	// and the resulting path is re-checked against the directory afterwards.
	rel := strings.TrimPrefix(strings.TrimPrefix(stored, "/"), "images/")
	clean := filepath.Clean("/" + rel)
	full := filepath.Join(h.uploadDir, clean)

	root, err := filepath.Abs(h.uploadDir)
	if err != nil {
		return nil, "", err
	}
	abs, err := filepath.Abs(full)
	if err != nil {
		return nil, "", err
	}
	if abs != root && !strings.HasPrefix(abs, root+string(os.PathSeparator)) {
		return nil, "", fmt.Errorf("path escapes the upload directory")
	}
	f, err := os.Open(abs)
	if err != nil {
		return nil, "", err
	}
	return f, contentTypeForPath(abs), nil
}

// downloadFilename picks the name the browser will save the file under: the
// last path segment, stripped of any query string, with a conservative
// fallback. Quotes and control characters cannot survive, so the header
// cannot be split by a crafted name.
func downloadFilename(stored string) string {
	name := stored
	if i := strings.IndexAny(name, "?#"); i >= 0 {
		name = name[:i]
	}
	// A path ending in a separator has no file component at all; Base would
	// hand back the parent directory's name, which is not a filename.
	if name == "" || strings.HasSuffix(name, "/") {
		return "download"
	}
	name = path.Base(name)
	name = strings.Map(func(r rune) rune {
		if r < 0x20 || r == '"' || r == '\\' || r == '/' {
			return -1
		}
		return r
	}, name)
	if name == "" || name == "." || name == ".." {
		return "download"
	}
	return name
}

// contentTypeForPath maps a filename to a content type, defaulting to a
// generic binary type rather than guessing.
func contentTypeForPath(p string) string {
	switch strings.ToLower(filepath.Ext(p)) {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".webp":
		return "image/webp"
	case ".gif":
		return "image/gif"
	case ".pdf":
		return "application/pdf"
	default:
		return "application/octet-stream"
	}
}
