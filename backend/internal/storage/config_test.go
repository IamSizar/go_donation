package storage

import (
	"strings"
	"testing"
)

// fullR2Env is a complete, valid R2 configuration. The secret is obviously
// fake and is a literal here rather than a real value read from anywhere: a
// test that needs a credential to run is a test nobody runs.
func fullR2Env() map[string]string {
	return map[string]string{
		"R2_ACCOUNT_ID":        "abc123account",
		"R2_ACCESS_KEY_ID":     "AKIAEXAMPLE",
		"R2_SECRET_ACCESS_KEY": "not-a-real-secret",
		"R2_BUCKET":            "humanitarian-media",
		"R2_PUBLIC_BASE_URL":   "https://media.example.org",
	}
}

func lookupFrom(env map[string]string) func(string) string {
	return func(k string) string { return env[k] }
}

// TestParseR2ConfigEmptyMeansLocalDisk pins the case every developer machine
// and every CI run depends on: an environment with none of the R2 variables is
// not an error, it selects local disk. If this ever starts erroring, the test
// suite and local development both stop working without credentials, which is
// the state that let the original data-loss bug go untested in the first place.
func TestParseR2ConfigEmptyMeansLocalDisk(t *testing.T) {
	cfg, err := ParseR2Config(func(string) string { return "" })
	if err != nil {
		t.Fatalf("empty environment must select local disk, got error: %v", err)
	}
	if cfg != nil {
		t.Fatalf("empty environment must return a nil config, got %+v", cfg)
	}
}

// TestParseR2ConfigWhitespaceOnlyIsAbsent pins that a variable set to spaces
// counts as unset rather than as present-but-blank.
//
// This is the shape a mistake actually takes: a Railway variable pasted with a
// trailing newline, or a .env line written as `R2_BUCKET= `. Treating that as
// "present" would produce a config that passes the all-or-nothing check and
// then fails on every single upload against a bucket named " ".
func TestParseR2ConfigWhitespaceOnlyIsAbsent(t *testing.T) {
	env := map[string]string{
		"R2_ACCOUNT_ID":        "   ",
		"R2_ACCESS_KEY_ID":     "\t",
		"R2_SECRET_ACCESS_KEY": "",
		"R2_BUCKET":            "\n",
		"R2_PUBLIC_BASE_URL":   " ",
	}
	cfg, err := ParseR2Config(lookupFrom(env))
	if err != nil || cfg != nil {
		t.Fatalf("all-whitespace environment must behave as unset; got cfg=%+v err=%v", cfg, err)
	}
}

// TestParseR2ConfigRefusesPartial is the most important test in this package.
//
// A half-configured R2 must stop the boot. If it instead falls back to local
// disk, the deploy goes green, uploads keep returning success, and the files
// keep being deleted by the next release — which is precisely the failure this
// whole migration exists to end, reintroduced through a typo. Every
// single-variable-missing combination is exercised, because the one that gets
// forgotten is never the one anybody predicted.
func TestParseR2ConfigRefusesPartial(t *testing.T) {
	for _, missing := range r2EnvVars {
		t.Run("missing_"+missing, func(t *testing.T) {
			env := fullR2Env()
			delete(env, missing)

			cfg, err := ParseR2Config(lookupFrom(env))
			if err == nil {
				t.Fatalf("a config missing %s must be refused, not accepted (cfg=%+v)", missing, cfg)
			}
			if cfg != nil {
				t.Fatalf("a refused config must return nil, got %+v", cfg)
			}
			if !strings.Contains(err.Error(), missing) {
				t.Errorf("the error must name the missing variable %q so the fix is one read; got: %v", missing, err)
			}
		})
	}
}

// TestParseR2ConfigErrorNeverLeaksTheSecret pins that the refusal message
// names KEYS and never VALUES.
//
// The error goes straight to log.Fatalf in main.go, and a boot log is one of
// the easiest places in a system for a credential to end up somewhere it
// cannot be recalled from — a build log, a screenshot in a chat, a support
// ticket. Naming which variable is missing is the whole point of the message;
// naming what the others contain is never part of it.
func TestParseR2ConfigErrorNeverLeaksTheSecret(t *testing.T) {
	env := fullR2Env()
	delete(env, "R2_BUCKET")

	_, err := ParseR2Config(lookupFrom(env))
	if err == nil {
		t.Fatal("expected a refusal for a partial config")
	}
	for _, secret := range []string{env["R2_SECRET_ACCESS_KEY"], env["R2_ACCESS_KEY_ID"]} {
		if strings.Contains(err.Error(), secret) {
			t.Fatalf("the refusal message must not contain a credential value; got: %v", err)
		}
	}
}

// TestParseR2ConfigAcceptsComplete checks the happy path, including the
// trailing-slash trim on the public base.
//
// The trim matters because the base is concatenated with an object key on
// every upload and the result is written into the database permanently. A
// double slash there is not cosmetic: it names an object whose key starts with
// an empty segment, which does not exist in the bucket.
func TestParseR2ConfigAcceptsComplete(t *testing.T) {
	env := fullR2Env()
	env["R2_PUBLIC_BASE_URL"] = "https://media.example.org/"

	cfg, err := ParseR2Config(lookupFrom(env))
	if err != nil {
		t.Fatalf("a complete config must be accepted, got: %v", err)
	}
	if cfg == nil {
		t.Fatal("a complete config must return a config")
	}
	if cfg.PublicBaseURL != "https://media.example.org" {
		t.Errorf("trailing slash must be trimmed from the public base; got %q", cfg.PublicBaseURL)
	}
	if cfg.Bucket != "humanitarian-media" || cfg.AccountID != "abc123account" {
		t.Errorf("config fields did not round-trip: %+v", cfg)
	}
}

// TestParseR2ConfigRejectsSchemelessPublicBase pins the validation that
// catches the single most plausible typo in this configuration.
//
// "media.example.org" is how a person says a hostname out loud, and setting
// R2_PUBLIC_BASE_URL to it would produce stored strings like
// "media.example.org/uploads/x.png". IsAbsoluteURL does not recognise those as
// absolute, so every client would treat one as a relative path and prefix its
// own API origin onto it — producing a permanently broken URL, in a database
// row, that nobody would think to re-check. Catching it at boot turns a data
// repair into a restart.
func TestParseR2ConfigRejectsSchemelessPublicBase(t *testing.T) {
	for _, bad := range []string{
		"media.example.org",
		"//media.example.org",
		"ftp://media.example.org",
		"https://",
	} {
		env := fullR2Env()
		env["R2_PUBLIC_BASE_URL"] = bad

		if cfg, err := ParseR2Config(lookupFrom(env)); err == nil {
			t.Errorf("R2_PUBLIC_BASE_URL=%q must be rejected as not an absolute http(s) URL; got cfg=%+v", bad, cfg)
		}
	}
}

// TestEndpointURL pins R2's S3 endpoint hostname format. It is asserted here
// rather than discovered in production by a DNS failure.
func TestEndpointURL(t *testing.T) {
	got := EndpointURL("  abc123account  ")
	want := "https://abc123account.r2.cloudflarestorage.com"
	if got != want {
		t.Errorf("EndpointURL = %q, want %q", got, want)
	}
}
