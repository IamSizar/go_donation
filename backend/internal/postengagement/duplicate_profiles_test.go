// duplicate_profiles_test.go — the comment lists and the activity feed must
// show each comment and each like once even when its author has two
// user_profiles rows (OPOS #26603).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows,
// and a plain join on it repeats every row it touches.
//
// Integration tests against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set. This package had no test file before.
package postengagement

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newDupTestPool connects to TEST_DATABASE_URL and brings it up to date with
// the real migrations.
func newDupTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping postengagement integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// makeDupProfileUser inserts a user with two profile rows (the older first).
func makeDupProfileUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		fmt.Sprintf("9647%08d", rand.Intn(100000000)),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id) })
	for _, name := range []string{"Oldest Profile Name", "Newer Duplicate Profile Name"} {
		if _, err := pool.Exec(ctx,
			`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, $2, '', '')`,
			id, name); err != nil {
			t.Fatalf("insert profile: %v", err)
		}
	}
	return id
}

// seedDupComment posts one approved comment and one like on a post id nothing
// else uses, from a user with two profile rows. media_posts is joined with a
// LEFT JOIN throughout, so the post row itself need not exist.
func seedDupComment(t *testing.T, pool *pgxpool.Pool) (userID, postID, commentID int64) {
	t.Helper()
	ctx := context.Background()
	userID = makeDupProfileUser(t, pool)
	postID = int64(900000000 + rand.Intn(90000000))
	if err := pool.QueryRow(ctx,
		`INSERT INTO post_comments (post_id, user_id, body, status) VALUES ($1, $2, 'said it once', 'approved') RETURNING id`,
		postID, userID,
	).Scan(&commentID); err != nil {
		t.Fatalf("insert comment: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO post_likes (post_id, user_id) VALUES ($1, $2)`, postID, userID); err != nil {
		t.Fatalf("insert like: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM post_comments WHERE post_id = $1`, postID)
		_, _ = pool.Exec(ctx, `DELETE FROM post_likes WHERE post_id = $1`, postID)
	})
	return userID, postID, commentID
}

func TestListCommentsShowsACommentOnceWhenItsAuthorHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	_, postID, _ := seedDupComment(t, pool)

	items, err := New(pool).ListComments(context.Background(), postID, true, 100)
	if err != nil {
		t.Fatalf("ListComments: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("got %d comments on post %d, want 1", len(items), postID)
	}
	if items[0].UserName != "Oldest Profile Name" {
		t.Errorf("UserName = %q, want the oldest profile row's name", items[0].UserName)
	}
}

func TestAdminListCommentsShowsACommentOnceWhenItsAuthorHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	_, _, commentID := seedDupComment(t, pool)

	items, err := New(pool).AdminListComments(context.Background(), "approved", 500)
	if err != nil {
		t.Fatalf("AdminListComments: %v", err)
	}
	got := 0
	for _, x := range items {
		if x.ID == commentID {
			got++
		}
	}
	if got != 1 {
		t.Fatalf("comment %d listed %d times, want 1", commentID, got)
	}
}

// TestActivityFeedShowsEachEventOnceWhenTheActorHasTwoProfiles covers both
// halves of the UNION: the comment branch and the like branch.
func TestActivityFeedShowsEachEventOnceWhenTheActorHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	userID, postID, _ := seedDupComment(t, pool)

	items, err := New(pool).ActivityFeed(context.Background(), "", 500)
	if err != nil {
		t.Fatalf("ActivityFeed: %v", err)
	}
	comments, likes := 0, 0
	for _, x := range items {
		if x.PostID != postID || x.UserID != userID {
			continue
		}
		switch x.Kind {
		case "comment":
			comments++
		case "like":
			likes++
		}
	}
	if comments != 1 {
		t.Errorf("the comment appeared %d times in the feed, want 1", comments)
	}
	if likes != 1 {
		t.Errorf("the like appeared %d times in the feed, want 1", likes)
	}
}
