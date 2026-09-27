// Migration 138 — a volunteer sends ID card, residence card and ration card as
// separate documents, each with a back side; all six must land in their own
// columns. Needs TEST_DATABASE_URL (see registration_photos_test.go).
package handlers

import (
	"bytes"
	"context"
	"fmt"
	"math/rand"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

func TestUploadPhotos_VolunteerDocumentsEachSaveFrontAndBack(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	var userID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, is_admin, staff_tier, registration_status, account_status)
		 VALUES ($1, 3, 1, 0, 'user', 'approved', 'active') RETURNING id`,
		fmt.Sprintf("99902%08d", rand.Intn(100000000))).Scan(&userID); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM user_profiles WHERE user_id = $1`, userID)
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, userID)
	})
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, 'Vol', '', '')`, userID); err != nil {
		t.Fatalf("insert user_profiles: %v", err)
	}

	gin.SetMode(gin.TestMode)
	h := &RegistrationHandler{Users: users.NewStore(pool), Store: &failingStorage{failOnSubstring: "never-matches"}}

	body := new(bytes.Buffer)
	w := multipart.NewWriter(body)
	png := []byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}
	fields := []string{"id_photo", "id_photo_back", "residence_card_photo", "residence_card_photo_back",
		"ration_card_photo", "ration_card_photo_back"}
	for _, f := range fields {
		part, _ := w.CreateFormFile(f, f+".png")
		_, _ = part.Write(png)
	}
	w.Close()

	req := httptest.NewRequest(http.MethodPost, "/api/registration/photos", body)
	req.Header.Set("Content-Type", w.FormDataContentType())
	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = req
	c.Set("auth.user", &auth.ResolvedUser{UserID: userID, RoleID: 3})
	h.UploadPhotos(c)

	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	cols := []string{"id_photo_path", "id_photo_back_path", "residence_card_photo_path",
		"residence_card_photo_back_path", "ration_card_photo_path", "ration_card_photo_back_path"}
	seen := map[string]bool{}
	for _, col := range cols {
		var v string
		if err := pool.QueryRow(ctx, `SELECT `+col+` FROM user_profiles WHERE user_id = $1`, userID).Scan(&v); err != nil {
			t.Fatalf("%s: %v", col, err)
		}
		if v == "" {
			t.Errorf("%s was not saved", col)
		}
		if seen[v] {
			t.Errorf("%s shares a stored path with another column (%q)", col, v)
		}
		seen[v] = true
	}

	// The migration also flips the volunteer rules.
	rules := map[string]string{}
	rows, _ := pool.Query(ctx, `SELECT field_key, state FROM registration_field_rules
		WHERE field_key IN ('volunteer_id_photo','volunteer_ration_card_photo',
		'volunteer_residence_card_photo','volunteer_golden_square_photo')`)
	defer rows.Close()
	for rows.Next() {
		var k, s string
		_ = rows.Scan(&k, &s)
		rules[k] = s
	}
	for _, k := range []string{"volunteer_id_photo", "volunteer_ration_card_photo", "volunteer_residence_card_photo"} {
		if rules[k] != "required" {
			t.Errorf("%s = %q, want required", k, rules[k])
		}
	}
	if rules["volunteer_golden_square_photo"] != "hidden" {
		t.Errorf("golden square rule = %q, want hidden", rules["volunteer_golden_square_photo"])
	}
}
