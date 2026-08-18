package storage

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// LocalStorage writes uploads to a directory on the machine running the
// server, and is the behaviour this codebase had before R2 existed.
//
// It is kept — rather than replaced — for two reasons that are not the same
// reason:
//
//  1. Development and the test suite must run with an empty environment. A
//     storage layer that needs credentials to exercise is a storage layer
//     nobody exercises, and the bug this whole package fixes was one that a
//     test could never have caught because there was nothing to catch it with.
//  2. Every row already in the database holds a path this backend produced,
//     of the form "images/uploads/….png" or "images/profile_7_….jpg", served
//     by r.Static("/images", uploadDir) in main.go. Those files still exist on
//     any deployment with a mounted volume, and those rows must keep
//     resolving. LocalStorage returns byte-for-byte the same strings the old
//     inline save code returned, so switching a deployment to R2 changes what
//     NEW uploads look like and changes nothing at all about old ones.
type LocalStorage struct {
	// Dir is the filesystem root uploads are written beneath — UPLOAD_DIR, or
	// "./images" when unset. It is the same directory main.go hands to
	// r.Static, which is what makes the returned paths resolvable.
	Dir string
}

// NewLocal returns a LocalStorage rooted at dir.
//
// It does not create the directory: the per-upload write does that (see Put),
// because the previous code created it per-upload too and a directory that
// exists at boot is no guarantee it still exists at upload time on a host
// where a volume can be remounted.
func NewLocal(dir string) *LocalStorage {
	return &LocalStorage{Dir: dir}
}

// staticURLPrefix is the route main.go mounts the upload directory on
// (r.Static("/images", uploadDir)), and therefore the prefix every relative
// stored path must carry to resolve.
//
// It is a constant here rather than a literal at three call sites because the
// old code repeated the string "images/" in each of the three handlers that
// saved a file, and three copies of a routing fact is three chances for one of
// them to drift away from the route it depends on.
const staticURLPrefix = "images/"

// Put writes r's bytes to <Dir>/<key> and returns the relative path a client
// stores and fetches by.
//
// contentType is accepted to satisfy the Storage interface and deliberately
// ignored: a file served by Gin's static handler gets its Content-Type sniffed
// from the filename at response time, so recording one here would be a value
// nothing ever reads. R2 is the backend where it matters.
//
// The write is direct rather than write-to-temp-then-rename. That matches
// exactly what the code being replaced did, and this is a storage migration,
// not an opportunity to change local-disk durability semantics on the way
// past.
func (s *LocalStorage) Put(ctx context.Context, key, contentType string, r io.Reader) (string, error) {
	safeKey, err := SanitizeKey(key)
	if err != nil {
		return "", err
	}

	// filepath.FromSlash converts the object key's forward slashes to the
	// host separator. On Linux and macOS this is a no-op; it is here so the
	// key format stays an object-storage concept that the disk backend
	// translates, rather than a path format that happens to match Unix.
	abs := filepath.Join(s.Dir, filepath.FromSlash(safeKey))

	// Create the parent directory rather than only s.Dir, because keys carry
	// prefixes: the admin upload endpoint writes "uploads/<name>", so the
	// destination is a level deeper than the root. The old code got away with
	// creating only the root because the admin handler assumed main.go had
	// already made ./images/uploads for it.
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		return "", fmt.Errorf("creating upload directory for %q: %w", safeKey, err)
	}

	dst, err := os.OpenFile(abs, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return "", fmt.Errorf("creating %q: %w", safeKey, err)
	}
	// Close is checked, not deferred-and-discarded: a write that fails only at
	// close (a full disk reports it there, not at Write) would otherwise
	// return success, and the caller would store a path to a truncated file.
	// That is the same class of failure as the one this package exists to fix
	// — a database row pointing at bytes that are not there.
	if _, err := io.Copy(dst, r); err != nil {
		dst.Close()
		os.Remove(abs)
		return "", fmt.Errorf("writing %q: %w", safeKey, err)
	}
	if err := dst.Close(); err != nil {
		os.Remove(abs)
		return "", fmt.Errorf("closing %q: %w", safeKey, err)
	}

	return staticURLPrefix + safeKey, nil
}

// Describe names the backend for the single startup log line in main.go.
func (s *LocalStorage) Describe() string {
	dir := strings.TrimSpace(s.Dir)
	if dir == "" {
		dir = "."
	}
	return "local disk at " + dir + " (served at /images/*)"
}
