package storage

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestLocalPutReturnsTheLegacyRelativePath is the compatibility test for the
// whole migration.
//
// Every row already in the database holds a string this backend produced, and
// those strings only resolve through r.Static("/images", uploadDir) in main.go.
// If the local backend ever returns a differently-shaped path, a deployment
// that has NOT moved to R2 starts writing rows that its own static route
// cannot serve — the same 404-behind-a-row symptom the migration is fixing,
// caused by the fix. The exact strings asserted here are the ones the three
// handlers returned before this package existed.
func TestLocalPutReturnsTheLegacyRelativePath(t *testing.T) {
	dir := t.TempDir()
	s := NewLocal(dir)

	cases := map[string]string{
		// admin_upload.go's key → what it used to build as "images/uploads/"+name
		"uploads/ab12cd34.png": "images/uploads/ab12cd34.png",
		// profile.go's key → what savePicture used to return as "images/"+unique
		"profile_7_1771234567.jpg": "images/profile_7_1771234567.jpg",
		// registration.go's key → what savePhoto used to return
		"idcard_42_1771234567.jpg": "images/idcard_42_1771234567.jpg",
	}
	for key, want := range cases {
		got, err := s.Put(context.Background(), key, "image/png", strings.NewReader("bytes"))
		if err != nil {
			t.Fatalf("Put(%q) errored: %v", key, err)
		}
		if got != want {
			t.Errorf("Put(%q) returned %q, want the legacy shape %q", key, got, want)
		}
		if IsAbsoluteURL(got) {
			t.Errorf("the local backend must return a RELATIVE path so clients prefix the API origin; got %q", got)
		}
	}
}

// TestLocalPutWritesTheBytesWhereTheStaticRouteLooks checks that the returned
// path and the file on disk actually agree.
//
// The returned path is "images/<key>" and the file is at "<UPLOAD_DIR>/<key>",
// and those two are only consistent because main.go mounts UPLOAD_DIR at the
// "/images" route. That relationship is invisible from either file alone,
// which is exactly the kind of coupling that gets broken by a well-meaning
// tidy-up, so it is asserted here.
func TestLocalPutWritesTheBytesWhereTheStaticRouteLooks(t *testing.T) {
	dir := t.TempDir()
	s := NewLocal(dir)

	const payload = "the actual file contents"
	stored, err := s.Put(context.Background(), "uploads/deadbeef.png", "image/png", strings.NewReader(payload))
	if err != nil {
		t.Fatalf("Put errored: %v", err)
	}

	// Strip the route prefix the way the static handler does, and the
	// remainder must be the path under UPLOAD_DIR.
	rel := strings.TrimPrefix(stored, "images/")
	onDisk := filepath.Join(dir, filepath.FromSlash(rel))
	got, err := os.ReadFile(onDisk)
	if err != nil {
		t.Fatalf("the returned path %q does not resolve to a file under %q: %v", stored, dir, err)
	}
	if string(got) != payload {
		t.Errorf("stored bytes = %q, want %q", got, payload)
	}
}

// TestLocalPutCreatesNestedPrefixes pins a real bug in the code this replaced.
//
// The admin upload handler wrote to <uploadDir>/uploads/<name> but only ever
// created <uploadDir> — it assumed something else had made the "uploads"
// subdirectory for it. On a fresh volume nothing had, so the very first upload
// after mounting one failed with an unhelpful "no such file or directory"
// while every later upload on a warm container succeeded. The backend now
// creates the key's parent, so a nested prefix works on an empty root.
func TestLocalPutCreatesNestedPrefixes(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "does", "not", "exist", "yet")
	s := NewLocal(dir)

	if _, err := s.Put(context.Background(), "uploads/nested.png", "image/png", strings.NewReader("x")); err != nil {
		t.Fatalf("Put into an uncreated nested prefix must succeed, got: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "uploads", "nested.png")); err != nil {
		t.Fatalf("expected the file to exist under the created prefix: %v", err)
	}
}

// TestLocalPutRefusesToEscapeTheUploadRoot checks that the traversal guard is
// actually wired into the write path, not merely available beside it.
//
// SanitizeKey is tested on its own; this asserts Put calls it. Two of the four
// upload paths derive their key from a client-supplied filename, so a Put that
// skipped the check would let an upload write anywhere the process can write.
func TestLocalPutRefusesToEscapeTheUploadRoot(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "uploads")
	s := NewLocal(dir)

	if _, err := s.Put(context.Background(), "../escaped.png", "image/png", strings.NewReader("x")); !errors.Is(err, ErrUnsafeKey) {
		t.Fatalf("a traversing key must be refused with ErrUnsafeKey, got: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "escaped.png")); !os.IsNotExist(err) {
		t.Fatal("a refused key must not have written anything outside the upload root")
	}
}

// TestLocalDescribeNamesTheDirectory pins that the startup log line an
// operator reads actually says where files are going.
//
// This is a low-stakes assertion protecting a high-stakes property: the
// original bug was invisible precisely because nothing at boot said where
// uploads went. The one line that now does must not silently become empty.
func TestLocalDescribeNamesTheDirectory(t *testing.T) {
	d := NewLocal("/mnt/data/images").Describe()
	if !strings.Contains(d, "/mnt/data/images") {
		t.Errorf("Describe must name the directory an operator needs to verify; got %q", d)
	}
}

// TestNewSelectsLocalWithoutCredentials pins the wiring main.go depends on:
// an empty environment yields the disk backend, constructed successfully, with
// no network call and no credentials. If this needed either, the test suite
// could not run it.
func TestNewSelectsLocalWithoutCredentials(t *testing.T) {
	s, err := New(context.Background(), func(string) string { return "" }, "./images")
	if err != nil {
		t.Fatalf("an unconfigured environment must yield local disk, got: %v", err)
	}
	if _, ok := s.(*LocalStorage); !ok {
		t.Fatalf("expected *LocalStorage, got %T", s)
	}
}

// TestNewRefusesPartialR2 pins that the boot-time refusal is reachable through
// the constructor main.go actually calls, not only through ParseR2Config. A
// guard that the real code path bypasses is not a guard.
func TestNewRefusesPartialR2(t *testing.T) {
	env := fullR2Env()
	delete(env, "R2_SECRET_ACCESS_KEY")

	s, err := New(context.Background(), lookupFrom(env), "./images")
	if err == nil {
		t.Fatalf("a partial R2 config must fail the boot, got backend %T", s)
	}
	if s != nil {
		t.Fatalf("a refused config must not return a usable backend, got %T", s)
	}
}
