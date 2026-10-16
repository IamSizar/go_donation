// channel_details_test.go — R2 #47–55: the details the new donation pages
// collect must be stored, and a gift with no usable amount must be refused
// instead of saved as an empty row (#54).
//
// The attachment-path test is pure; the rest need a throwaway Postgres and are
// skipped unless TEST_DATABASE_URL is set.
package donations

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestValidAttachment(t *testing.T) {
	ok := []string{
		"images/uploads/0a1b2c3d4e5f60718293a4b5c6d7e8f9.jpg",
		"https://pub-abc.r2.dev/uploads/0a1b2c3d4e5f60718293a4b5c6d7e8f9.png",
	}
	bad := []string{
		"",
		"   ",
		"data:image/png;base64,AAAA",
		"file:///etc/passwd",
		"http://evil.example/uploads/x.jpg",      // not https
		"https://evil.example/not-uploads/x.jpg", // not an uploads path
		"images/uploads/../../etc/passwd",        // traversal
		"images/uploads/x.jpg\"><script>alert(1)</script>", // markup
		"/images/uploads/x.jpg",                            // absolute local path
	}
	for _, p := range ok {
		if !ValidAttachment(p) {
			t.Errorf("ValidAttachment(%q) = false, want true", p)
		}
	}
	for _, p := range bad {
		if ValidAttachment(p) {
			t.Errorf("ValidAttachment(%q) = true, want false", p)
		}
	}
}

func makeDonor(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		fmt.Sprintf("9647%08d", rand.Intn(100000000)),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM donations WHERE user_id = $1`, id)
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

func strp(s string) *string { return &s }

// TestInsertRefusesAnAmountItCannotStore pins #54: these used to save an
// empty-amount row and report success.
func TestInsertRefusesAnAmountItCannotStore(t *testing.T) {
	pool := newDupTestPool(t)
	st := NewStore(pool)
	uid := makeDonor(t, pool)

	for _, amt := range []string{"", "0", "-5", "abc", "10000000001"} {
		_, err := st.Insert(context.Background(), uid, nil, strp("m"), strp(amt), strp("Cash"), "general", nil, "")
		if !errors.Is(err, ErrInvalidAmount) {
			t.Errorf("amount %q: err = %v, want ErrInvalidAmount", amt, err)
		}
	}
	var n int
	_ = pool.QueryRow(context.Background(), `SELECT COUNT(*) FROM donations WHERE user_id = $1`, uid).Scan(&n)
	if n != 0 {
		t.Fatalf("%d rows were saved for refused amounts, want 0", n)
	}
}

// TestInsertAcceptsALargeIQDAmount: 1,500,000 IQD (about 1,150 USD) is an
// ordinary gift. The old ceiling of 1,000,000 silently emptied it.
func TestInsertAcceptsALargeIQDAmount(t *testing.T) {
	pool := newDupTestPool(t)
	st := NewStore(pool)
	uid := makeDonor(t, pool)

	ins, err := st.Insert(context.Background(), uid, nil, strp("m"), strp("1500000"), strp("Cash"), "general", nil, "")
	if err != nil {
		t.Fatalf("Insert: %v", err)
	}
	var amount string
	_ = pool.QueryRow(context.Background(), `SELECT amount FROM donations WHERE id = $1`, ins.ID).Scan(&amount)
	if amount != "1500000" {
		t.Fatalf("stored amount = %q, want 1500000", amount)
	}
}

func TestSetChannelDetailsStoresOnlyKnownValues(t *testing.T) {
	pool := newDupTestPool(t)
	st := NewStore(pool)
	ctx := context.Background()
	uid := makeDonor(t, pool)
	other := makeDonor(t, pool)

	ins, err := st.Insert(ctx, uid, nil, strp("m"), strp("25000"), strp("Zain"), "general", nil, "")
	if err != nil {
		t.Fatalf("Insert: %v", err)
	}

	if err := st.SetChannelDetails(ctx, ins.ID, uid, ChannelDetails{
		Channel: "balance_transfer", TransferKind: "card", Network: "Zain",
		SerialNumber: "1234-5678", AttachmentPath: "images/uploads/aa.jpg",
		DonorPhone: "07701234567", Currency: "usd",
	}); err != nil {
		t.Fatalf("SetChannelDetails: %v", err)
	}
	var channel, kind, network, serial, att, phone, cur *string
	_ = pool.QueryRow(ctx, `SELECT channel, transfer_kind, network, serial_number, attachment_path, donor_phone, currency
	                          FROM donations WHERE id = $1`, ins.ID).Scan(&channel, &kind, &network, &serial, &att, &phone, &cur)
	want := map[string]*string{"channel": channel, "transfer_kind": kind, "network": network,
		"serial_number": serial, "attachment_path": att, "donor_phone": phone, "currency": cur}
	exp := map[string]string{"channel": "balance_transfer", "transfer_kind": "card", "network": "zain",
		"serial_number": "1234-5678", "attachment_path": "images/uploads/aa.jpg",
		"donor_phone": "07701234567", "currency": "USD"}
	for k, v := range exp {
		if want[k] == nil || *want[k] != v {
			t.Errorf("%s = %v, want %q", k, want[k], v)
		}
	}

	// Junk is dropped, not stored: unknown channel, a foreign attachment, a
	// transfer kind on a non-transfer channel.
	if err := st.SetChannelDetails(ctx, ins.ID, uid, ChannelDetails{
		Channel: "bitcoin", TransferKind: "card", Network: "vodafone",
		AttachmentPath: "https://evil.example/x.jpg",
	}); err != nil {
		t.Fatalf("SetChannelDetails junk: %v", err)
	}
	_ = pool.QueryRow(ctx, `SELECT channel, transfer_kind, network, attachment_path, currency FROM donations WHERE id = $1`,
		ins.ID).Scan(&channel, &kind, &network, &att, &cur)
	if channel != nil || kind != nil || network != nil || att != nil {
		t.Errorf("junk stored: channel=%v kind=%v network=%v attachment=%v", channel, kind, network, att)
	}
	if cur == nil || *cur != "IQD" {
		t.Errorf("currency = %v, want IQD default", cur)
	}

	// Another donor cannot write onto this row.
	if err := st.SetChannelDetails(ctx, ins.ID, other, ChannelDetails{Channel: "cash", VisitNote: "hijack"}); err != nil {
		t.Fatalf("SetChannelDetails other: %v", err)
	}
	var note *string
	_ = pool.QueryRow(ctx, `SELECT visit_note FROM donations WHERE id = $1`, ins.ID).Scan(&note)
	if note != nil {
		t.Errorf("another donor wrote visit_note = %q", *note)
	}
}
