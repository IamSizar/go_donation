package assistant

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// anthropicClient is a minimal client for the Anthropic Messages API. We keep
// it dependency-free (net/http only) so the assistant adds no new modules.
type anthropicClient struct {
	apiKey string
	model  string
	http   *http.Client
}

func newAnthropicClient(apiKey, model string) *anthropicClient {
	if model == "" {
		model = "claude-3-5-haiku-latest"
	}
	return &anthropicClient{
		apiKey: apiKey,
		model:  model,
		http:   &http.Client{Timeout: 30 * time.Second},
	}
}

// chatMessage mirrors the {role, content} shape the API expects. role is
// "user" or "assistant".
type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type anthropicRequest struct {
	Model     string        `json:"model"`
	MaxTokens int           `json:"max_tokens"`
	System    string        `json:"system"`
	Messages  []chatMessage `json:"messages"`
}

type anthropicResponse struct {
	Content []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	Error *struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error"`
}

// complete sends the system prompt + conversation and returns the model's raw
// text output (which we expect to be a JSON object per our system prompt).
func (a *anthropicClient) complete(ctx context.Context, system string, msgs []chatMessage) (string, error) {
	reqBody := anthropicRequest{
		Model:     a.model,
		MaxTokens: 700,
		System:    system,
		Messages:  msgs,
	}
	raw, err := json.Marshal(reqBody)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.anthropic.com/v1/messages", bytes.NewReader(raw))
	if err != nil {
		return "", err
	}
	req.Header.Set("content-type", "application/json")
	req.Header.Set("x-api-key", a.apiKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	resp, err := a.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	var parsed anthropicResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return "", fmt.Errorf("assistant: bad LLM response (%d): %s", resp.StatusCode, truncate(string(body), 200))
	}
	if parsed.Error != nil {
		return "", fmt.Errorf("assistant: LLM error: %s", parsed.Error.Message)
	}
	if resp.StatusCode != http.StatusOK || len(parsed.Content) == 0 {
		return "", fmt.Errorf("assistant: LLM HTTP %d", resp.StatusCode)
	}

	// Concatenate any text blocks.
	var out string
	for _, c := range parsed.Content {
		if c.Type == "text" {
			out += c.Text
		}
	}
	return out, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
