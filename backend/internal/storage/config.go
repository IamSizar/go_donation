package storage

import (
	"fmt"
	"net/url"
	"sort"
	"strings"
)

// R2Config is the complete set of values needed to talk to a Cloudflare R2
// bucket over its S3-compatible API, plus the public host the stored objects
// are read back from.
//
// SecretAccessKey is a credential. It is never logged, never returned from an
// API handler, and never included in Describe() — see r2Storage.Describe.
type R2Config struct {
	// AccountID is the Cloudflare account the bucket belongs to. It is not a
	// secret, but it is what the S3 endpoint hostname is built from:
	// https://<AccountID>.r2.cloudflarestorage.com
	AccountID string

	AccessKeyID     string
	SecretAccessKey string

	// Bucket is the R2 bucket name objects are written into.
	Bucket string

	// PublicBaseURL is the origin (optionally with a path prefix) that serves
	// the bucket publicly — either a custom domain bound to the bucket or its
	// r2.dev URL. This is NOT the S3 endpoint: the S3 endpoint is
	// authenticated and is for writing; this is what an app or a browser
	// fetches an image from. Getting these two confused produces stored URLs
	// that 401 forever, so they are two separate variables on purpose.
	PublicBaseURL string
}

// r2EnvVars lists every environment variable that configures R2, in the order
// they are reported to an operator.
var r2EnvVars = []string{
	"R2_ACCOUNT_ID",
	"R2_ACCESS_KEY_ID",
	"R2_SECRET_ACCESS_KEY",
	"R2_BUCKET",
	"R2_PUBLIC_BASE_URL",
}

// ParseR2Config decides, from the environment alone, whether R2 is configured.
//
// It takes a lookup function rather than reading os.Getenv directly so the
// decision is a pure function of its input and can be unit-tested for every
// combination of present and absent variables without setting a single real
// environment variable. This is the same shape as normalizeUsername in
// internal/handlers/admin_status.go: the rule is separated from the world so
// the rule can be proven.
//
// Three outcomes, and the middle one is the entire point:
//
//   - NONE of the five variables set → (nil, nil). Local disk. This is what a
//     developer's machine and the test suite get, with no credentials and no
//     network, exactly as before.
//   - ALL five set and well-formed → (*R2Config, nil). Object storage.
//   - SOME set → (nil, error), and main.go refuses to boot.
//
// That third case is not pedantry about configuration hygiene, it is the whole
// reason this package was written. The failure this migration fixes was silent
// data loss: uploads went somewhere that stopped existing, and nothing
// reported a problem until a user opened a photo that was already gone. A
// partial R2 config would reproduce that failure precisely — a typo'd or
// forgotten variable name would fall back to a container-local directory, the
// deploy would look healthy, uploads would keep succeeding, and the files
// would keep vanishing on every release. Refusing to start is loud, immediate,
// and costs an operator one restart; falling back costs users their documents
// and nobody notices for a week.
//
// The error names the missing variables so the fix is one read, and it names
// only the KEYS — never a value, since three of these five are credentials.
func ParseR2Config(lookup func(string) string) (*R2Config, error) {
	vals := make(map[string]string, len(r2EnvVars))
	var present, missing []string
	for _, k := range r2EnvVars {
		v := strings.TrimSpace(lookup(k))
		vals[k] = v
		if v == "" {
			missing = append(missing, k)
		} else {
			present = append(present, k)
		}
	}

	// Nothing configured at all: local disk, no complaint. Development and CI
	// must keep working with an empty environment.
	if len(present) == 0 {
		return nil, nil
	}

	if len(missing) > 0 {
		sort.Strings(present)
		sort.Strings(missing)
		return nil, fmt.Errorf(
			"R2 storage is partially configured: %s set, but %s missing. "+
				"Set all of %s to use Cloudflare R2, or none of them to use local disk (UPLOAD_DIR). "+
				"Refusing to start rather than silently writing uploads to a container filesystem that is deleted on every deploy",
			strings.Join(present, ", "),
			strings.Join(missing, ", "),
			strings.Join(r2EnvVars, ", "),
		)
	}

	cfg := &R2Config{
		AccountID:       vals["R2_ACCOUNT_ID"],
		AccessKeyID:     vals["R2_ACCESS_KEY_ID"],
		SecretAccessKey: vals["R2_SECRET_ACCESS_KEY"],
		Bucket:          vals["R2_BUCKET"],
		PublicBaseURL:   strings.TrimRight(vals["R2_PUBLIC_BASE_URL"], "/"),
	}

	// The public base is validated here rather than at first upload because
	// its value is written into the database. A base of "cdn.example.org"
	// (scheme forgotten — an easy mistake, since that is how one says a
	// hostname out loud) would produce stored strings like
	// "cdn.example.org/uploads/x.png", which IsAbsoluteURL does not recognise
	// as absolute, so every client would treat it as a relative path and
	// prefix its own API origin onto it. The result is a permanently broken
	// URL in a row nobody will think to re-check. Catching it at boot means
	// the mistake costs a restart instead of a data repair.
	u, err := url.Parse(cfg.PublicBaseURL)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
		return nil, fmt.Errorf(
			"R2_PUBLIC_BASE_URL must be an absolute http(s) URL such as https://media.example.org "+
				"(this is the public host that serves the bucket — a custom domain or the r2.dev URL — "+
				"not the S3 API endpoint); got %q", cfg.PublicBaseURL)
	}

	return cfg, nil
}

// EndpointURL is the S3-compatible API endpoint for an R2 account.
//
// Cloudflare gives every account one endpoint host and addresses buckets as a
// path beneath it, which is why the bucket name does not appear here and why
// the client is configured for path-style addressing (see NewR2). Kept as a
// one-line pure function so the hostname format is asserted by a test rather
// than discovered in production by a DNS failure.
func EndpointURL(accountID string) string {
	return "https://" + strings.TrimSpace(accountID) + ".r2.cloudflarestorage.com"
}
