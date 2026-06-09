package notify

import (
	"bytes"
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// fcmClient holds the long-lived state for talking to FCM HTTP v1.
type fcmClient struct {
	projectID  string
	clientEmail string
	privateKey *rsa.PrivateKey
	httpClient *http.Client

	mu           sync.Mutex
	accessToken  string
	tokenExpires time.Time
}

// fcmDisabledError signals that no service account is configured.
type fcmDisabledError struct{}

func (fcmDisabledError) Error() string { return "FCM not configured" }

// errFCMDisabled is returned from Notifier.SendPushDirect when no
// FIREBASE_CREDENTIALS_FILE is configured.
var errFCMDisabled = fcmDisabledError{}

type serviceAccountFile struct {
	Type        string `json:"type"`
	ProjectID   string `json:"project_id"`
	PrivateKey  string `json:"private_key"`
	ClientEmail string `json:"client_email"`
	TokenURI    string `json:"token_uri"`
}

// loadFCMClient reads the Firebase service-account JSON and prepares an FCM
// client. Returns (nil, nil) if no credentials file is configured.
func loadFCMClient() (*fcmClient, error) {
	path := strings.TrimSpace(os.Getenv("FIREBASE_CREDENTIALS_FILE"))
	if path == "" {
		path = "./firebase-credentials.json"
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var sa serviceAccountFile
	if err := json.Unmarshal(data, &sa); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if sa.Type != "service_account" {
		return nil, fmt.Errorf("%s: expected type=service_account, got %q", path, sa.Type)
	}
	if sa.ProjectID == "" || sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, fmt.Errorf("%s: missing required fields", path)
	}

	block, _ := pem.Decode([]byte(sa.PrivateKey))
	if block == nil {
		return nil, errors.New("could not PEM-decode private_key")
	}
	var pk *rsa.PrivateKey
	if parsed, perr := x509.ParsePKCS8PrivateKey(block.Bytes); perr == nil {
		rsaKey, ok := parsed.(*rsa.PrivateKey)
		if !ok {
			return nil, errors.New("private_key is not RSA")
		}
		pk = rsaKey
	} else {
		rsaKey, rerr := x509.ParsePKCS1PrivateKey(block.Bytes)
		if rerr != nil {
			return nil, fmt.Errorf("parse private_key: %w / %w", perr, rerr)
		}
		pk = rsaKey
	}

	return &fcmClient{
		projectID:  sa.ProjectID,
		clientEmail: sa.ClientEmail,
		privateKey: pk,
		httpClient: &http.Client{Timeout: 15 * time.Second},
	}, nil
}

// accessTokenFor returns a cached OAuth2 access token for the messaging scope,
// refreshing when within 60 s of expiry.
func (c *fcmClient) accessTokenFor(ctx context.Context) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.accessToken != "" && time.Until(c.tokenExpires) > time.Minute {
		return c.accessToken, nil
	}

	now := time.Now()
	claims := jwt.MapClaims{
		"iss":   c.clientEmail,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   "https://oauth2.googleapis.com/token",
		"iat":   now.Unix(),
		"exp":   now.Add(time.Hour).Unix(),
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	signed, err := tok.SignedString(c.privateKey)
	if err != nil {
		return "", fmt.Errorf("sign jwt: %w", err)
	}

	form := url.Values{}
	form.Set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
	form.Set("assertion", signed)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://oauth2.googleapis.com/token",
		strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("oauth post: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("oauth %d: %s", resp.StatusCode, string(body))
	}
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return "", fmt.Errorf("parse oauth response: %w", err)
	}
	c.accessToken = out.AccessToken
	c.tokenExpires = time.Now().Add(time.Duration(out.ExpiresIn) * time.Second)
	return c.accessToken, nil
}

// SendResult is the outcome of sending a single push.
type SendResult struct {
	DeviceToken string `json:"device_token"`
	OK          bool   `json:"ok"`
	MessageName string `json:"message_name,omitempty"`
	Error       string `json:"error,omitempty"`
}

// sendOne sends a notification to a single device token.
func (c *fcmClient) sendOne(ctx context.Context, token, title, body, imageURL string) SendResult {
	r := SendResult{DeviceToken: token}
	accessToken, err := c.accessTokenFor(ctx)
	if err != nil {
		r.Error = err.Error()
		return r
	}

	notif := map[string]any{"title": title, "body": body}
	if imageURL != "" {
		notif["image"] = imageURL
	}

	// Build the APNs block explicitly. Without this, FCM v1 forwards a
	// stripped-down payload to APNs and iOS often silently drops it —
	// especially in the Simulator and especially when the app is in the
	// foreground. The shape below is what Firebase's own iOS docs recommend:
	//
	//   apns.headers.apns-priority   = 10  → "deliver immediately"
	//   apns.headers.apns-push-type  = alert → standard user-visible push
	//   apns.payload.aps.alert       = {title, body} → what iOS displays
	//   apns.payload.aps.sound       = "default" → makes the device chime
	//   apns.payload.aps.mutable-content = 1 → lets Notification Service
	//                                         Extensions modify the alert
	//                                         (e.g. download an image)
	apsAlert := map[string]any{"title": title, "body": body}
	apsBlock := map[string]any{
		"alert":            apsAlert,
		"sound":            "default",
		"mutable-content":  1,
	}
	apnsBlock := map[string]any{
		"headers": map[string]any{
			"apns-priority":  "10",
			"apns-push-type": "alert",
		},
		"payload": map[string]any{
			"aps": apsBlock,
		},
	}
	if imageURL != "" {
		// FCM forwards `fcm_options.image` to the iOS Notification Service
		// Extension which downloads + attaches the image to the alert.
		apnsBlock["fcm_options"] = map[string]any{"image": imageURL}
	}

	payload := map[string]any{
		"message": map[string]any{
			"token":        token,
			"notification": notif,
			"android": map[string]any{
				"priority": "high",
				"notification": map[string]any{
					"sound":         "default",
					"default_sound": true,
				},
			},
			"apns": apnsBlock,
		},
	}
	buf, _ := json.Marshal(payload)
	url := "https://fcm.googleapis.com/v1/projects/" + c.projectID + "/messages:send"

	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(buf))
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		r.Error = err.Error()
		return r
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		var ok struct {
			Name string `json:"name"`
		}
		_ = json.Unmarshal(respBody, &ok)
		r.OK = true
		r.MessageName = ok.Name
		return r
	}
	r.Error = fmt.Sprintf("HTTP %d: %s", resp.StatusCode, string(respBody))
	return r
}
