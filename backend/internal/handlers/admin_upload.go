package handlers

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"image"
	"image/jpeg"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
	xdraw "golang.org/x/image/draw"

	"github.com/karam-flutter/humanitarian-backend/internal/storage"
)

// AdminUploadHandler serves Phase 15's POST /api/admin/upload endpoint. The
// mobile app's volunteer check-in photo also arrives here, via POST
// /api/uploads, so this one handler is the destination for both the dashboard's
// uploads and the app's evidence photos.
//
// Flow:
//  1. Read the multipart "file" field.
//  2. Validate the extension (only images + PDF for case documents).
//  3. Validate the size (configurable; defaults to 5 MB).
//  4. Generate a random 32-hex name, preserve original extension.
//  5. Hand the bytes to the configured storage backend under "uploads/<name>".
//  6. Return {success, path, size, mime} where `path` is what the SPA
//     stores back into the corresponding column (e.g. partners.logo_path).
//
// Step 5 used to be "write to <uploadDir>/uploads/<name>", and that is what
// this handler is being changed away from. The container filesystem it wrote
// to is replaced on every Railway deploy, so every release silently deleted
// every file this endpoint had ever accepted while the database went on
// holding the paths — including the volunteer check-in photo whose 404,
// minutes after a successful upload, is how the whole problem was found. See
// internal/storage for the full account.
//
// What the caller does with `path` is unchanged and needs no client change,
// because `path` is now whatever the backend returned rather than a string
// this handler builds:
//
//	local disk → "images/uploads/<name>", relative, served by
//	             r.Static("/images", uploadDir) exactly as before
//	R2         → "https://<public base>/uploads/<name>", absolute
//
// Both clients already pass an absolute URL through untouched and prefix their
// API origin onto anything else, so the two shapes coexist in one column.
type AdminUploadHandler struct {
	// Store is where the bytes go. Never nil — main.go builds one backend at
	// startup and every upload path in the process shares it.
	Store       storage.Storage
	MaxBytes    int64
	allowedExts map[string]string
}

func NewAdminUploadHandler(store storage.Storage) *AdminUploadHandler {
	return &AdminUploadHandler{
		Store:    store,
		MaxBytes: 5 * 1024 * 1024, // 5 MB
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

	// The object key. "uploads/" is a prefix inside the storage backend, not a
	// directory this handler has to create: the local backend makes the parent
	// directory itself, and on R2 a prefix is just part of the key. The old
	// code depended on main.go (or a human) having created ./images/uploads
	// beforehand, which is a dependency that fails silently on a fresh volume.
	key := "uploads/" + name

	// Section 27 — automatically compress JPEG uploads (typical phone photos /
	// profile images) to cut storage + speed up loading, UNLESS the caller
	// flags the file as sensitive (medical reports, case documents, house /
	// property images, official documents) — those keep their original bytes
	// for inspection/verification. PNG/GIF/WEBP/SVG/PDF are stored untouched
	// (transparency / vector / document integrity). Any compression failure
	// falls back to storing the original file, so uploads never break.
	//
	// The compressor now returns the re-encoded bytes instead of writing them
	// to a path, because the destination is no longer necessarily a path. That
	// also removes the os.Stat that used to measure the result: the size we
	// report is the length of what we actually stored, which is knowable
	// without asking a filesystem that may not be involved.
	var body io.ReadSeeker
	size := file.Size
	if (ext == ".jpg" || ext == ".jpeg") && !isSensitiveUpload(c) {
		if compressed, err := compressJPEG(file); err == nil {
			body = bytes.NewReader(compressed)
			size = int64(len(compressed))
		}
	}
	if body == nil {
		src, err := file.Open()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"success": false,
				"error":   "Failed to save file: " + err.Error(),
			})
			return
		}
		defer src.Close()
		body = src
	}

	// Path the SPA stores back into the row. Whatever the backend hands back
	// goes into the response verbatim — a relative "images/uploads/<name>" on
	// local disk, matching how existing seed paths look
	// (e.g. "images/seed/foo.png"), or an absolute R2 URL. Rebuilding it here
	// would defeat the whole arrangement.
	storedPath, err := h.Store.Put(c.Request.Context(), key, mime, body)
	if err != nil {
		// The driver error names a bucket, a filesystem path, or an S3 status
		// code, none of which is actionable by the person who pressed Upload.
		// It goes to the log; they get a sentence they can act on. (The old
		// code appended err.Error() to the response — kept for the
		// file.Open failure above, which is a local decode-level problem, but
		// not for a storage backend that can name infrastructure.)
		log.Printf("[upload] storing %q failed: %v", key, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Could not save the file. Please try again.",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"path":    storedPath,
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

// compressJPEG decodes an uploaded JPEG and re-encodes it at a reduced quality,
// returning the new bytes. Returns an error if the input can't be decoded, so
// the caller can fall back to storing the original bytes verbatim.
//
// This used to be saveCompressedJPEG and wrote straight to a destination path.
// It returns bytes now because the destination is a storage backend that may
// not be a filesystem at all — and returning bytes is strictly safer than the
// old shape besides: the previous version could create the destination file
// and only then fail inside jpeg.Encode, leaving a truncated image at a path
// the caller had already decided to keep. Nothing partial can escape a
// function that hands back a finished buffer or an error.
func compressJPEG(file *multipart.FileHeader) ([]byte, error) {
	src, err := file.Open()
	if err != nil {
		return nil, err
	}
	defer src.Close()
	img, err := jpeg.Decode(src)
	if err != nil {
		return nil, err
	}
	// Downscale oversized photos so the longest side is at most maxImageDim.
	// Profile/gallery photos from phones are often 3000–4000px; 1600px is ample
	// for any dashboard/app display and cuts storage + load time further. Images
	// already within the limit are left at their native size. (Sensitive uploads
	// never reach this function — the caller skips compression for them.)
	img = downscaleToMax(img, maxImageDim)
	// Quality 82 is visually near-lossless for photos but typically 40–60%
	// smaller than a phone camera's default ~95.
	var out bytes.Buffer
	if err := jpeg.Encode(&out, img, &jpeg.Options{Quality: 82}); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
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
