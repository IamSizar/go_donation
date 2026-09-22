// engagement_test.go — client note, 2026-09-22: no like/comment/share on
// marriage-seeker profile cards. Pins two things: the engagement primitives
// themselves, and that List() reports them correctly per-viewer — the whole
// point of a "liked_by_me" flag is that it differs by who's asking, and it
// depended on a pre-existing gap: GET /api/marriage carried no auth
// middleware, so the viewer was always nil regardless of the caller's
// Bearer token (fixed in cmd/server/main.go alongside this feature).
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set, same
// harness as owner_test.go / field_privacy_test.go:
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_test?sslmode=disable' \
//	  go test ./internal/marriage/ -run Engagement -v
package marriage

import (
	"context"
	"testing"
)

func TestToggleLikeFlipsAndCounts(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	viewer := makeUser(t, pool)
	profileID := makeProfile(t, pool, owner, "employee_only", nil)
	store := NewEngagementStore(pool)

	liked, count, err := store.ToggleLike(context.Background(), profileID, viewer)
	if err != nil {
		t.Fatalf("ToggleLike (like): %v", err)
	}
	if !liked || count != 1 {
		t.Fatalf("first toggle: liked=%v count=%d, want true/1", liked, count)
	}

	liked, count, err = store.ToggleLike(context.Background(), profileID, viewer)
	if err != nil {
		t.Fatalf("ToggleLike (unlike): %v", err)
	}
	if liked || count != 0 {
		t.Fatalf("second toggle: liked=%v count=%d, want false/0", liked, count)
	}
}

// TestListReportsLikedByMePerViewer is the regression test for the auth-gap
// fix: two different viewers of the SAME profile must see two different
// liked_by_me values, and an unauthenticated viewer (id 0) must see false
// rather than erroring.
func TestListReportsLikedByMePerViewer(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	liker := makeUser(t, pool)
	stranger := makeUser(t, pool)
	profileID := makeProfile(t, pool, owner, "employee_only", nil)

	store := NewEngagementStore(pool)
	if _, _, err := store.ToggleLike(context.Background(), profileID, liker); err != nil {
		t.Fatalf("ToggleLike: %v", err)
	}

	listStore := New(pool)
	asLiker, err := listStore.List(context.Background(), SearchFilters{Status: "all", ViewerUserID: liker, Limit: 100})
	if err != nil {
		t.Fatalf("List (liker): %v", err)
	}
	p := find(t, asLiker, profileID)
	if !p.LikedByMe || p.LikeCount != 1 {
		t.Fatalf("as liker: liked_by_me=%v like_count=%d, want true/1", p.LikedByMe, p.LikeCount)
	}

	asStranger, err := listStore.List(context.Background(), SearchFilters{Status: "all", ViewerUserID: stranger, Limit: 100})
	if err != nil {
		t.Fatalf("List (stranger): %v", err)
	}
	p = find(t, asStranger, profileID)
	if p.LikedByMe || p.LikeCount != 1 {
		t.Fatalf("as stranger: liked_by_me=%v like_count=%d, want false/1 (count is shared, the flag is not)", p.LikedByMe, p.LikeCount)
	}

	asAnonymous, err := listStore.List(context.Background(), SearchFilters{Status: "all", ViewerUserID: 0, Limit: 100})
	if err != nil {
		t.Fatalf("List (anonymous): %v", err)
	}
	p = find(t, asAnonymous, profileID)
	if p.LikedByMe {
		t.Fatalf("as anonymous (viewer 0): liked_by_me=true, want false")
	}
}

func TestCommentCountAndShareCountOnList(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	commenter := makeUser(t, pool)
	profileID := makeProfile(t, pool, owner, "employee_only", nil)

	engage := NewEngagementStore(pool)
	if _, err := engage.AddComment(context.Background(), profileID, commenter, "hello", "approved", false); err != nil {
		t.Fatalf("AddComment: %v", err)
	}
	// A pending (held) comment must NOT count toward the public comment_count
	// — same rule as media posts: only 'approved' rows are counted/shown.
	if _, err := engage.AddComment(context.Background(), profileID, commenter, "held one", "pending", true); err != nil {
		t.Fatalf("AddComment (pending): %v", err)
	}
	if _, err := engage.IncrementShare(context.Background(), profileID); err != nil {
		t.Fatalf("IncrementShare: %v", err)
	}
	if _, err := engage.IncrementShare(context.Background(), profileID); err != nil {
		t.Fatalf("IncrementShare (again): %v", err)
	}

	items, err := New(pool).List(context.Background(), SearchFilters{Status: "all", ViewerUserID: owner, Limit: 100})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	p := find(t, items, profileID)
	if p.CommentCount != 1 {
		t.Fatalf("comment_count = %d, want 1 (the pending one must not count)", p.CommentCount)
	}
	if p.ShareCount != 2 {
		t.Fatalf("share_count = %d, want 2", p.ShareCount)
	}
}
