package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"image"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
	xdraw "golang.org/x/image/draw"
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

	// Section 27 — automatically compress JPEG uploads (typical phone photos /
	// profile images) to cut storage + speed up loading, UNLESS the caller
	// flags the file as sensitive (medical reports, case documents, house /
	// property images, official documents) — those keep their original bytes
	// for inspection/verification. PNG/GIF/WEBP/SVG/PDF are stored untouched
	// (transparency / vector / document integrity). Any compression failure
	// falls back to saving the original file, so uploads never break.
	saved := false
	if (ext == ".jpg" || ext == ".jpeg") && !isSensitiveUpload(c) {
		if err := saveCompressedJPEG(file, dest); err == nil {
			saved = true
		}
	}
	if !saved {
		if err := c.SaveUploadedFile(file, dest); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"success": false,
				"error":   "Failed to save file: " + err.Error(),
			})
			return
		}
	}

	// Report the actual on-disk size (compression may have shrunk it).
	size := file.Size
	if fi, statErr := os.Stat(dest); statErr == nil {
		size = fi.Size()
	}

	// Path the SPA stores back into the row: relative, no leading slash, so
	// it matches how existing seed paths look (e.g. "images/seed/foo.png").
	relPath := "images/uploads/" + name
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"path":    relPath,
		"size":    size,
		"mime":    mime,
	})
}

// isSensitiveUpload reports whether an upload must retain its original bytes
// (no compression). Callers signal this with either sensitive=1/true or a
// kind of medical/case-document/property/official (Section 27).
func isSensitiveUpload(c *gin.Context) bool {
	s := strings.ToLower(strings.TrimSpace(c.PostForm("sensitive")))
	if s == "1" || s == "true" || s == "yes" {
		return true
	}
	switch strings.ToLower(strings.TrimSpace(c.PostForm("kind"))) {
	case "medical", "medical_report", "case_document", "document",
		"property", "house", "official":
		return true
	}
	return false
}

// saveCompressedJPEG decodes an uploaded JPEG and re-encodes it at a reduced
// quality to the destination path. Returns an error (without writing a partial
// file the caller would keep) if the input can't be decoded, so the caller can
// fall back to storing the original bytes verbatim.
func saveCompressedJPEG(file *multipart.FileHeader, dest string) error {
	src, err := file.Open()
	if err != nil {
		return err
	}
	defer src.Close()
	img, err := jpeg.Decode(src)
	if err != nil {
		return err
	}
	// Downscale oversized photos so the longest side is at most maxImageDim.
	// Profile/gallery photos from phones are often 3000–4000px; 1600px is ample
	// for any dashboard/app display and cuts storage + load time further. Images
	// already within the limit are left at their native size. (Sensitive uploads
	// never reach this function — the caller skips compression for them.)
	img = downscaleToMax(img, maxImageDim)
	out, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer out.Close()
	// Quality 82 is visually near-lossless for photos but typically 40–60%
	// smaller than a phone camera's default ~95.
	return jpeg.Encode(out, img, &jpeg.Options{Quality: 82})
}

// maxImageDim is the longest-side cap (px) applied to compressible uploads.
const maxImageDim = 1600

// downscaleToMax returns img scaled so its longest side is <= maxDim, preserving
// aspect ratio with high-quality resampling. Returns img unchanged when it is
// already within the cap (no upscaling).
func downscaleToMax(img image.Image, maxDim int) image.Image {
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	if w <= maxDim && h <= maxDim || w <= 0 || h <= 0 {
		return img
	}
	nw, nh := w, h
	if w >= h {
		nw = maxDim
		nh = int(float64(h) * float64(maxDim) / float64(w))
	} else {
		nh = maxDim
		nw = int(float64(w) * float64(maxDim) / float64(h))
	}
	if nw < 1 {
		nw = 1
	}
	if nh < 1 {
		nh = 1
	}
	dst := image.NewRGBA(image.Rect(0, 0, nw, nh))
	xdraw.CatmullRom.Scale(dst, dst.Bounds(), img, b, xdraw.Over, nil)
	return dst
}
