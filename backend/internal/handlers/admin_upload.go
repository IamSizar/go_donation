package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

// AdminUploadHandler serves Phase 15's POST /api/admin/upload endpoint.
//
// Flow:
//   1. Read the multipart "file" field.
//   2. Validate the extension (only images + PDF for case documents).
//   3. Validate the size (configurable; defaults to 5 MB).
//   4. Generate a random 32-hex name, preserve original extension.
//   5. Save to <uploadDir>/uploads/<name><ext>.
//   6. Return {success, path, size, mime} where `path` is what the SPA
//      stores back into the corresponding column (e.g. partners.logo_path).
//
// Storage layout matches the Gin static handler in main.go:
//
//   ./images                  ← uploadDir, served at GET /images/*
//   ./images/uploads          ← where this handler writes
//   ./images/seed/...         ← pre-existing seed files (not touched)
//
// So after a successful upload the SPA can render the new image via
// `<img src={`/${path}`} />` immediately.
type AdminUploadHandler struct {
	UploadDir   string
	MaxBytes    int64
	allowedExts map[string]string
}

func NewAdminUploadHandler(uploadDir string) *AdminUploadHandler {
	return &AdminUploadHandler{
		UploadDir: uploadDir,
		MaxBytes:  5 * 1024 * 1024, // 5 MB
		// extension → mime (mime is informational; we don't sniff content
		// since we serve as static files only — Gin will set the response
		// Content-Type from the filename when served back).
		allowedExts: map[string]string{
			".png":  "image/png",
			".jpg":  "image/jpeg",
			".jpeg": "image/jpeg",
			".gif":  "image/gif",
			".webp": "image/webp",
			".svg":  "image/svg+xml",
			".pdf":  "application/pdf",
		},
	}
}

func (h *AdminUploadHandler) Upload(c *gin.Context) {
	// Cap the request body so a malicious upload can't OOM us before we
	// even read the form.
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, h.MaxBytes+1024)

	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   `Missing "file" field in multipart form.`,
		})
		return
	}
	if file.Size > h.MaxBytes {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "File too large (max 5 MB).",
		})
		return
	}

	ext := strings.ToLower(filepath.Ext(file.Filename))
	mime, ok := h.allowedExts[ext]
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Unsupported file type. Allowed: png, jpg, jpeg, gif, webp, svg, pdf.",
		})
		return
	}

	// 16 random bytes → 32 hex chars. crypto/rand is already used elsewhere
	// in this codebase (auth/token.go), so no new dependency.
	rnd := make([]byte, 16)
	if _, err := rand.Read(rnd); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to generate filename: " + err.Error(),
		})
		return
	}
	name := hex.EncodeToString(rnd) + ext

	// Save under <UploadDir>/uploads. The directory is created by the
	// startup code in main.go (or manually); we don't mkdir on every upload.
	dest := filepath.Join(h.UploadDir, "uploads", name)
	if err := c.SaveUploadedFile(file, dest); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to save file: " + err.Error(),
		})
		return
	}

	// Path the SPA stores back into the row: relative, no leading slash, so
	// it matches how existing seed paths look (e.g. "images/seed/foo.png").
	relPath := "images/uploads/" + name
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"path":    relPath,
		"size":    file.Size,
		"mime":    mime,
	})
}
