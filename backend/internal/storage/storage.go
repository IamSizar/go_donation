// Package storage owns every write of a user-uploaded file, and it exists
// because the previous answer to "where do uploads go" was "next to the
// binary", which on this deployment meant "nowhere, as of the next deploy".
//
// uploadDir was hardcoded to "./images" — the container's own working
// directory. Railway replaces the container filesystem on every release, so
// each deploy silently deleted every file any user had ever uploaded: profile
// photos, ID cards, medical reports, partner logos, volunteer check-in
// evidence. Nothing failed loudly. The database kept the paths, so a row went
// on claiming a photo existed while the URL behind it answered 404, which
// reads to everyone looking at it as a broken image viewer rather than as data
// that is simply gone. It was found when a volunteer's check-in photo 404'd
// minutes after uploading successfully — a backend deploy had landed in
// between and taken the directory with it.
//
// Pointing UPLOAD_DIR at a mounted volume is the stopgap; this package is the
// fix. Object storage (Cloudflare R2) has no relationship to the container's
// lifetime at all, so there is no directory left to lose.
//
// The package deliberately contains two implementations behind one interface:
//
//	local.go — writes under a directory on disk, exactly as before. This is
//	           what development and the test suite use, so neither needs R2
//	           credentials or a network to run.
//	r2.go    — writes to a Cloudflare R2 bucket over the S3-compatible API.
//	           This is what production uses.
//
// Which one is live is decided once at startup by ParseR2Config (config.go),
// from environment variables only.
package storage

import (
	"context"
	"errors"
	"io"
	"mime"
	"path"
	"strings"
)

// Storage is the one thing every upload path in this codebase is allowed to
// know about its own destination.
//
// Put writes the bytes read from r under key, and returns the URL a client
// should be given to fetch them back. That return value is the important half
// of the contract and the reason the interface is shaped this way rather than
// as a plain "write this file": the two backends return DIFFERENT SHAPES of
// URL, and callers must store whatever they are handed verbatim rather than
// rebuilding it.
//
//	local disk → a RELATIVE path, e.g. "images/uploads/ab12….png", which the
//	             r.Static("/images", uploadDir) route in main.go serves. This
//	             is byte-for-byte what the handlers stored before this package
//	             existed, so every pre-existing database row keeps its meaning.
//	R2         → an ABSOLUTE URL, e.g.
//	             "https://cdn.example.org/uploads/ab12….png", built from
//	             R2_PUBLIC_BASE_URL.
//
// Both shapes therefore coexist in the same database column, and a reader
// tells them apart by exactly one test: does the stored value start with
// "http://" or "https://"? If yes it is already a complete URL and must be
// used untouched; if no it is relative to the API origin. Both clients already
// apply precisely that test (admin-web's assetUrl, and the Flutter photo-URL
// helpers), which is why this migration needs no client change.
//
// key is a forward-slash object path with NO leading slash and no "images/"
// prefix — e.g. "uploads/ab12….png" or "profile_7_1771234567.jpg". The
// "images/" prefix is a local-disk serving detail and is added by the local
// backend alone; putting it in the key would bake a filesystem layout into R2
// object names for no reason.
//
// contentType is advisory for the local backend (Gin infers the response type
// from the filename when serving a static file) and load-bearing for R2, where
// an object stored without one is served back as application/octet-stream and
// a browser downloads it instead of displaying it. Pass "" to let the backend
// infer it from the key's extension.
type Storage interface {
	// Put stores the contents of r and returns the client-facing URL or path.
	// It returns an error without leaving a partially written object visible
	// to a caller that would then store its path.
	Put(ctx context.Context, key, contentType string, r io.Reader) (string, error)

	// Describe returns a short human-readable description of where this
	// backend writes, for the one startup log line that tells an operator
	// which of the two is live. It NEVER includes a credential.
	Describe() string
}

// ErrUnsafeKey is returned when a caller offers an object key that could
// escape its intended prefix.
//
// This is not theoretical caution. Two of the four call sites build the key
// from an uploaded file's own extension (filepath.Ext of a name the client
// chose), and on the local-disk backend a key is joined onto a directory path
// before being opened for writing. A key containing ".." would therefore write
// outside UPLOAD_DIR — and on R2 it would at minimum create objects at a path
// no cleanup routine expects. Rejecting the key is the only correct answer:
// there is no legitimate upload whose name needs a parent-directory segment.
var ErrUnsafeKey = errors.New("storage: unsafe object key")

// SanitizeKey validates and canonicalises an object key, or explains why it
// cannot be stored.
//
// It is deliberately a pure function taking and returning a string, so the
// rule can be tested exhaustively without a disk, a bucket, or a network — the
// interesting decisions in this package are all shaped this way.
//
// The rules, and why each exists:
//   - Backslashes become forward slashes. Object keys are URL paths, not
//     filesystem paths; a Windows-style separator arriving from a client's
//     filename would otherwise become a literal character in the key on R2 and
//     a separator on local disk, so the same upload would land in two
//     different places depending on the backend.
//   - Leading slashes are stripped. "/uploads/x.png" and "uploads/x.png" name
//     the same object, and allowing both would produce an R2 bucket with an
//     empty-named top-level "directory".
//   - path.Clean collapses "." and doubled separators so two spellings of one
//     key cannot become two objects.
//   - Anything that still contains a ".." segment, or is empty, or is
//     absolute, is rejected outright rather than repaired. A key that needed
//     repairing at this point is a key nobody meant to write.
func SanitizeKey(key string) (string, error) {
	k := strings.ReplaceAll(strings.TrimSpace(key), "\\", "/")
	k = strings.TrimLeft(k, "/")
	if k == "" {
		return "", ErrUnsafeKey
	}
	k = path.Clean(k)
	// path.Clean turns a fully-traversing key like "a/../.." into "..", and
	// leaves any unresolvable leading traversal in place, so this single check
	// after cleaning catches every remaining escape.
	if k == "." || k == ".." || strings.HasPrefix(k, "../") || strings.Contains(k, "/../") || strings.HasSuffix(k, "/..") {
		return "", ErrUnsafeKey
	}
	if strings.HasPrefix(k, "/") {
		return "", ErrUnsafeKey
	}
	return k, nil
}

// ContentTypeForKey guesses the MIME type an object should be served with,
// from its extension.
//
// This matters on R2 and did not matter before. A file on local disk is served
// by Gin's static handler, which sniffs the type at response time from the
// filename; an object in a bucket carries whatever Content-Type it was stored
// with, forever. Store a JPEG with no type and R2 hands it back as
// application/octet-stream, at which point every browser and every
// Image.network in the app treats a profile photo as a file to download rather
// than a picture to draw. The registration and profile upload paths never
// computed a MIME type at all, so without this they would store every photo
// wrong.
//
// The explicit table covers the types this system actually accepts (see
// AdminUploadHandler.allowedExts) rather than trusting mime.TypeByExtension
// for them, because that function consults the host's /etc/mime.types and so
// can answer differently on a developer's Mac and in the Alpine container —
// a stored Content-Type that depends on which machine ran the upload is a bug
// waiting for a confusing afternoon. Anything outside the table falls back to
// the standard library, and then to application/octet-stream, which is the
// honest answer for bytes we cannot identify.
func ContentTypeForKey(key string) string {
	ext := strings.ToLower(path.Ext(key))
	switch ext {
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	case ".svg":
		return "image/svg+xml"
	case ".pdf":
		return "application/pdf"
	}
	if t := mime.TypeByExtension(ext); t != "" {
		return t
	}
	return "application/octet-stream"
}

// JoinPublicURL builds the absolute URL a stored object is fetched from, given
// the configured public base and the object's key.
//
// Pure, and separated from the R2 client for that reason: URL joining is where
// this migration is most likely to go quietly wrong, and getting it wrong
// produces a URL that is stored in the database permanently. The two failure
// modes it guards are a base written with a trailing slash
// ("https://cdn.example.org/") and a key that has picked up a leading one —
// either alone is harmless, together they produce a double slash, and a double
// slash in an R2 path is not cosmetic: it names an object whose key begins
// with an empty segment, which does not exist.
//
// A base carrying a path prefix ("https://example.org/media") is preserved,
// since a custom domain may serve the bucket from a subpath.
func JoinPublicURL(base, key string) string {
	b := strings.TrimRight(strings.TrimSpace(base), "/")
	k := strings.TrimLeft(strings.TrimSpace(key), "/")
	if k == "" {
		return b
	}
	return b + "/" + k
}

// IsAbsoluteURL reports whether a stored media path is already a complete URL
// (an R2 object) rather than a path relative to the API origin (a legacy
// local-disk row).
//
// This is THE rule by which the two shapes coexist, written down once in Go so
// that any future backend reader applies the same test the two clients already
// apply on their side. Nothing in the backend currently needs to branch on it
// — handlers return the stored string untouched — but a caller that ever does
// must use this and not a hand-rolled prefix check.
func IsAbsoluteURL(stored string) bool {
	s := strings.ToLower(strings.TrimSpace(stored))
	return strings.HasPrefix(s, "http://") || strings.HasPrefix(s, "https://")
}
