// Pins what happens when a user presses "Message the staff team".
//
// TWO DEFECTS, BOTH INVISIBLE FROM THE APP
//  1. The thread was created 'pending', like a donor↔owner request that needs
//     the other party's consent. Support has no consent question, and a
//     pending thread refuses messages (POST /chats/:id/messages answers 409),
//     so the app opened a conversation into which the user's message could not
//     be sent. It could only be unblocked by someone accepting it IN THE APP,
//     which is not where staff work.
//  2. Nothing on the row said it was a support request, so the only list that
//     could show it was the donor↔owner oversight page, with the requests
//     mixed in and unmarked.
package handlers

import (
	"context"
	"testing"

	"github.com/karam-flutter/humanitarian-backend/internal/chat"
)

func TestSupportThreadOpensActiveAndMarked(t *testing.T) {
	pool := newAuthTestPool(t)
	store := &chat.Store{Pool: pool}
	ctx := context.Background()

	user := insertAccount(t, pool, "user", "")
	staff := insertAccount(t, pool, "user", "")

	thread, isNew, err := store.RequestSupportThread(ctx, user.id, staff.id)
	if err != nil {
		t.Fatalf("open support thread: %v", err)
	}
	if !isNew {
		t.Error("the first call must report the thread as newly created — it is what triggers the staff notification")
	}
	if thread.Status != "active" {
		t.Errorf(
			"support thread opened %q. Anything but 'active' means the user's "+
				"message is refused with a 409 by the endpoint they were just "+
				"sent to.", thread.Status,
		)
	}

	var kind string
	if err := pool.QueryRow(ctx,
		`SELECT kind FROM chat_threads WHERE id = $1`, thread.ID).Scan(&kind); err != nil {
		t.Fatalf("read kind: %v", err)
	}
	if kind != "support" {
		t.Errorf("thread kind = %q; unmarked rows cannot be listed by the support view", kind)
	}
}

// Pressing the tile twice must not open a second conversation, and must not
// re-notify staff — the app calls this on every tap, including when the user
// is simply returning to a chat they already have open.
func TestSupportThreadIsReusedNotDuplicated(t *testing.T) {
	pool := newAuthTestPool(t)
	store := &chat.Store{Pool: pool}
	ctx := context.Background()

	user := insertAccount(t, pool, "user", "")
	staff := insertAccount(t, pool, "user", "")

	first, _, err := store.RequestSupportThread(ctx, user.id, staff.id)
	if err != nil {
		t.Fatalf("first: %v", err)
	}
	second, isNew, err := store.RequestSupportThread(ctx, user.id, staff.id)
	if err != nil {
		t.Fatalf("second: %v", err)
	}
	if second.ID != first.ID {
		t.Errorf("a second tap opened thread %d instead of reusing %d", second.ID, first.ID)
	}
	if isNew {
		t.Error("the reused thread was reported as new — staff would be notified again on every tap")
	}
}

// The whole point of the kind column: the two audiences get two lists, and
// neither shows the other's rows.
func TestAdminListsSeparateSupportFromDonorThreads(t *testing.T) {
	pool := newAuthTestPool(t)
	store := &chat.Store{Pool: pool}
	ctx := context.Background()

	user := insertAccount(t, pool, "user", "")
	staff := insertAccount(t, pool, "user", "")
	donor := insertAccount(t, pool, "user", "")
	owner := insertAccount(t, pool, "user", "")

	support, _, err := store.RequestSupportThread(ctx, user.id, staff.id)
	if err != nil {
		t.Fatalf("support thread: %v", err)
	}
	direct, _, _, err := store.RequestThread(ctx, donor.id, owner.id, nil, donor.id)
	if err != nil {
		t.Fatalf("donor thread: %v", err)
	}

	has := func(items []chat.AdminThreadView, id int64) bool {
		for _, it := range items {
			if it.ID == id {
				return true
			}
		}
		return false
	}

	donorList, err := store.ListAllThreads(ctx, "", "direct")
	if err != nil {
		t.Fatalf("list direct: %v", err)
	}
	supportList, err := store.ListAllThreads(ctx, "", "support")
	if err != nil {
		t.Fatalf("list support: %v", err)
	}

	if !has(donorList, direct.ID) {
		t.Error("the donor oversight list lost its own thread")
	}
	if has(donorList, support.ID) {
		t.Error("a support request is still in the donor list — this is the mixing the split removes")
	}
	if !has(supportList, support.ID) {
		t.Error("the support view does not list the support request, which is its only job")
	}
	if has(supportList, direct.ID) {
		t.Error("a donor↔owner thread leaked into the support view")
	}

	// An unrecognised kind must not mean "everything": a typo in a query
	// parameter would otherwise silently restore the mixed list.
	fallback, err := store.ListAllThreads(ctx, "", "banana")
	if err != nil {
		t.Fatalf("list with a nonsense kind: %v", err)
	}
	if has(fallback, support.ID) {
		t.Error("an unknown kind included support rows; it must fall back to 'direct'")
	}
}
