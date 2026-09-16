// registration_photos_test.go — OPOS #25276.
//
// "Photo picked at registration sometimes doesn't display."
//
// ROOT CAUSE: UploadPhotos used to return 400 the instant ANY ONE field
// failed to save, BEFORE persisting any field that had already saved
// successfully. personal_photo was the worst-hit case: SetGrantorPhotos ran
// only after BOTH personal_photo and id_photo had been processed, so a
// failing id_photo threw away an already-saved personal_photo's path -- the
// file existed in storage, but user_profiles.profile_picture was never
// updated, so the picture never displayed anywhere.
//
// THE FIX makes every field independent: a failure is recorded in
// failed_fields and every field that DID save gets written to the database
// regardless of what happened to any other field in the same request.
//
// Integration test, skipped unless TEST_DATABASE_URL is set (same convention
// as auth_verified_factor_test.go):
//
//	createdb godonation_regphotos_test
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_regphotos_test?sslmode=disable' \
//	  go test ./internal/handlers/ -run RegistrationPhotos -v
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// failingStorage saves every key except ones containing failOnSubstring,
// which return an error -- a deterministic stand-in for "this one file's
// save genuinely fails" without needing a real broken filesystem.
type failingStorage struct {
	failOnSubstring string
}

func (s *failingStorage) Put(_ context.Context, key, _ string, _ io.Reader) (string, error) {
	if strings.Contains(key, s.failOnSubstring) {
		return "", errors.New("simulated storage failure")
	}
	return "uploads/" + key, nil
}
func (s *failingStorage) Describe() string { return "failingStorage (test)" }

func TestUploadPhotos_OneFieldFailingDoesNotDiscardAnothersAlreadySavedPath(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	phone := fmt.Sprintf("99901%08d", rand.Intn(100000000))
	var userID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, is_admin, staff_tier, registration_status, account_status)
		 VALUES ($1, 1, 1, 0, 'user', 'approved', 'active') RETURNING id`, phone).Scan(&userID); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM user_profiles WHERE user_id = $1`, userID)
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, userID)
	})
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, 'Test User', '', '')`, userID); err != nil {
		t.Fatalf("insert user_profiles: %v", err)
	}

	gin.SetMode(gin.TestMode)
	h := &RegistrationHandler{
		Users: users.NewStore(pool),
		// personal_photo saves fine; id_photo's save is made to fail. This
		// mirrors the exact real-world shape: a fine everyday photo next to
		// one attachment that fails for its own reasons (size, format, a
		// flaky upstream write).
		Store: &failingStorage{failOnSubstring: "idcard"},
	}

	body := new(bytes.Buffer)
	w := multipart.NewWriter(body)
	png := []byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}
	for _, field := range []string{"personal_photo", "id_photo"} {
		part, err := w.CreateFormFile(field, field+".png")
		if err != nil {
			t.Fatal(err)
		}
		if _, err := part.Write(png); err != nil {
			t.Fatal(err)
		}
	}
	w.Close()

	req := httptest.NewRequest(http.MethodPost, "/api/registration/photos", body)
	req.Header.Set("Content-Type", w.FormDataContentType())

	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = req
	c.Set("auth.user", &auth.ResolvedUser{UserID: userID, RoleID: 1})

	h.UploadPhotos(c)

	if rec.Code != http.StatusOK {
		t.Fatalf("status %d, want 200 (a partial failure is still an overall 200 with failed_fields set): %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("response is not JSON: %v", err)
	}
	failedFields, _ := resp["failed_fields"].([]any)
	foundIDPhotoFailure := false
	for _, f := range failedFields {
		if f == "id_photo" {
			foundIDPhotoFailure = true
		}
	}
	if !foundIDPhotoFailure {
		t.Errorf("failed_fields = %v, want it to name id_photo", failedFields)
	}
	if resp["personal_photo_set"] != true {
		t.Errorf("personal_photo_set = %v, want true — the field that succeeded must be reported as saved", resp["personal_photo_set"])
	}

	// THE ACTUAL REGRESSION: query the database directly, not just the
	// response. This is what the old code got wrong -- the response could
	// claim nothing was wrong while the write silently never happened.
	var stored string
	if err := pool.QueryRow(ctx,
		`SELECT profile_picture FROM user_profiles WHERE user_id = $1`, userID).Scan(&stored); err != nil {
		t.Fatalf("query profile_picture: %v", err)
	}
	if !strings.Contains(stored, "personal") {
		t.Errorf("profile_picture = %q, want it to contain the saved personal photo's path "+
			"— a failing id_photo must not discard an already-saved personal_photo", stored)
	}
}
