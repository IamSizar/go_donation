// Migration 137 — each identity document on the events profile is its own
// front + back pair. Needs TEST_DATABASE_URL like field_privacy_test.go.
package marriage

import (
	"context"
	"testing"
)

func TestSetProfileDetailsStoresEachIdentityDocumentSide(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "employee_only", nil)
	s := &Store{Pool: pool}
	ctx := context.Background()

	want := map[string]string{
		"id_photo_url":            "/uploads/id-front.jpg",
		"id_photo_back_url":       "/uploads/id-back.jpg",
		"residence_card_url":      "/uploads/res-front.jpg",
		"residence_card_back_url": "/uploads/res-back.jpg",
		"ration_card_url":         "/uploads/ration-front.jpg",
		"ration_card_back_url":    "/uploads/ration-back.jpg",
	}
	if err := s.SetProfileDetails(ctx, id, MarriageProfileDetails{
		IDPhotoURL: want["id_photo_url"], IDPhotoBackURL: want["id_photo_back_url"],
		ResidenceCardURL: want["residence_card_url"], ResidenceCardBackURL: want["residence_card_back_url"],
		RationCardURL: want["ration_card_url"], RationCardBackURL: want["ration_card_back_url"],
	}); err != nil {
		t.Fatalf("SetProfileDetails: %v", err)
	}
	got := map[string]string{}
	var a, b, c, d, e, f string
	if err := pool.QueryRow(ctx,
		`SELECT id_photo_url, id_photo_back_url, residence_card_url,
		        residence_card_back_url, ration_card_url, ration_card_back_url
		   FROM marriage_profiles WHERE id = $1`, id).Scan(&a, &b, &c, &d, &e, &f); err != nil {
		t.Fatal(err)
	}
	got["id_photo_url"], got["id_photo_back_url"], got["residence_card_url"] = a, b, c
	got["residence_card_back_url"], got["ration_card_url"], got["ration_card_back_url"] = d, e, f
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %q, want %q", k, got[k], v)
		}
	}

	// A later save with blanks must not wipe the photos (COALESCE/NULLIF).
	if err := s.SetProfileDetails(ctx, id, MarriageProfileDetails{}); err != nil {
		t.Fatal(err)
	}
	var kept string
	_ = pool.QueryRow(ctx, `SELECT id_photo_back_url FROM marriage_profiles WHERE id=$1`, id).Scan(&kept)
	if kept != want["id_photo_back_url"] {
		t.Errorf("blank re-save wiped id_photo_back_url: %q", kept)
	}

	// The three rules exist, required, and the merged one is hidden.
	rules := map[string]string{}
	rows, err := pool.Query(ctx, `SELECT field_key, state FROM registration_field_rules
		WHERE field_key IN ('marriage_id_photo','marriage_residence_card_photo',
		'marriage_ration_card_photo','marriage_golden_square')`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var k, st string
		_ = rows.Scan(&k, &st)
		rules[k] = st
	}
	for _, k := range []string{"marriage_id_photo", "marriage_residence_card_photo", "marriage_ration_card_photo"} {
		if rules[k] != "required" {
			t.Errorf("%s state = %q, want required", k, rules[k])
		}
	}
	if rules["marriage_golden_square"] != "hidden" {
		t.Errorf("marriage_golden_square state = %q, want hidden", rules["marriage_golden_square"])
	}
}
