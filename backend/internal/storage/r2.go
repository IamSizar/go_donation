package storage

import (
	"bytes"
	"context"
	"fmt"
	"io"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// r2Storage writes uploads to a Cloudflare R2 bucket over R2's S3-compatible
// API, and is the production backend.
//
// It is unexported because nothing outside this package should construct one
// directly — New() (see New below) is the only way to get a Storage, and it is
// the function that enforces "all five variables or none".
type r2Storage struct {
	client *s3.Client
	cfg    R2Config
}

// r2Region is the region every R2 request is signed for.
//
// R2 is a single global namespace with no regions, but SigV4 signing has no
// concept of "no region" and refuses to sign without one, so Cloudflare
// documents the literal string "auto". It is a signing input, not a location:
// changing it does not move data anywhere, it just produces a signature R2
// rejects.
const r2Region = "auto"

// NewR2 builds an R2-backed Storage from a validated config.
//
// Three deliberate deviations from a default AWS S3 client, each of which is
// required for R2 rather than merely tidy:
//
//  1. BaseEndpoint points at https://<account>.r2.cloudflarestorage.com.
//     Without it the SDK resolves an amazonaws.com hostname and the requests
//     go to Amazon, where these credentials mean nothing.
//  2. UsePathStyle. R2 addresses buckets as a path under the account endpoint
//     (endpoint/bucket/key). The SDK defaults to virtual-host style
//     (bucket.endpoint/key), which for R2 is a hostname that does not resolve.
//  3. RequestChecksumCalculationWhenRequired. Recent AWS SDK versions compute
//     a CRC32 checksum on every upload by default and send the body using
//     aws-chunked transfer encoding to carry it in a trailer. R2's S3 surface
//     does not accept that encoding, and the symptom is an opaque
//     signature/format error on every PutObject rather than anything naming
//     checksums — so this is set explicitly, and this comment is the reason it
//     must not be "cleaned up" later.
//
// Credentials are supplied statically from the config rather than through the
// ambient AWS credential chain on purpose: an EC2/ECS metadata lookup or a
// stray ~/.aws/credentials file silently taking precedence over the configured
// R2 keys would be a very long debugging session.
func NewR2(ctx context.Context, cfg R2Config) (Storage, error) {
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx,
		awsconfig.WithRegion(r2Region),
		awsconfig.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider(cfg.AccessKeyID, cfg.SecretAccessKey, ""),
		),
	)
	if err != nil {
		// The error from the SDK never contains the secret, only the reason a
		// provider could not be assembled, so it is safe to wrap and surface.
		return nil, fmt.Errorf("building R2 client for bucket %q: %w", cfg.Bucket, err)
	}

	client := s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(EndpointURL(cfg.AccountID))
		o.UsePathStyle = true
		o.RequestChecksumCalculation = aws.RequestChecksumCalculationWhenRequired
	})

	return &r2Storage{client: client, cfg: cfg}, nil
}

// Put uploads the bytes read from r as an object under key, and returns the
// absolute public URL a client fetches it from.
//
// The body handling is the one subtle part. PutObject needs to know the
// content length and, on a retry, needs to replay the body from the start —
// so it needs a seekable reader. Every caller in this codebase already has
// one: the registration and profile handlers pass multipart.File (which is an
// io.ReadSeeker), and the admin upload handler passes a *bytes.Reader over the
// re-encoded JPEG. The fallback below therefore almost never runs, but it must
// exist and must be correct, because silently uploading a zero-length or
// truncated object would put an unreadable URL into the database — the exact
// class of failure this package was written to end. Buffering is bounded in
// practice by the handlers' own size limits (the admin endpoint caps the
// request body at 5 MB before this is reached).
func (s *r2Storage) Put(ctx context.Context, key, contentType string, r io.Reader) (string, error) {
	safeKey, err := SanitizeKey(key)
	if err != nil {
		return "", err
	}
	if contentType == "" {
		contentType = ContentTypeForKey(safeKey)
	}

	body, ok := r.(io.ReadSeeker)
	if !ok {
		buf, readErr := io.ReadAll(r)
		if readErr != nil {
			return "", fmt.Errorf("reading upload for %q: %w", safeKey, readErr)
		}
		body = bytes.NewReader(buf)
	}

	if _, err := s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(s.cfg.Bucket),
		Key:         aws.String(safeKey),
		Body:        body,
		ContentType: aws.String(contentType),
	}); err != nil {
		// The key is safe to name in an error (it is a random filename we
		// generated); the credentials are not, and the SDK does not include
		// them. Handlers still translate this into a friendly message rather
		// than passing it to a user — see each call site.
		return "", fmt.Errorf("uploading %q to R2 bucket %q: %w", safeKey, s.cfg.Bucket, err)
	}

	return JoinPublicURL(s.cfg.PublicBaseURL, safeKey), nil
}

// Describe names the backend for the startup log line.
//
// It reports the bucket and the public base URL — both non-secret, and both
// the things an operator actually needs to confirm they configured the
// deployment they meant to. It reports NEITHER the access key id nor the
// secret: a log line is the easiest place in a system for a credential to end
// up somewhere it cannot be recalled from.
func (s *r2Storage) Describe() string {
	return fmt.Sprintf("Cloudflare R2 bucket %q, public base %s", s.cfg.Bucket, s.cfg.PublicBaseURL)
}

// New is the single entry point main.go uses to obtain the process's Storage.
//
// It reads the environment exactly once, through ParseR2Config, and returns
// either the R2 backend or the local-disk one. An error here is fatal at the
// call site by design: a partial R2 configuration must stop the boot, because
// the alternative — quietly writing to a container filesystem that the next
// deploy deletes — is the failure this package exists to make impossible.
func New(ctx context.Context, lookupEnv func(string) string, localDir string) (Storage, error) {
	cfg, err := ParseR2Config(lookupEnv)
	if err != nil {
		return nil, err
	}
	if cfg == nil {
		return NewLocal(localDir), nil
	}
	return NewR2(ctx, *cfg)
}
