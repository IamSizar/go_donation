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
		model = "claude-sonnet-5"
	}
	return &anthropicClient{
		apiKey: apiKey,
		model:  model,
		// Longer than the old plain-completion timeout: a tool-use turn can
		// take several model round-trips.
		http: &http.Client{Timeout: 45 * time.Second},
	}
}

// contentBlock is one block of a message's content array. Anthropic messages
// always use the array form here (never the plain-string shorthand) so the
// same type covers plain text, tool_use (the model asking to call a tool),
// and tool_result (our answer fed back to it).
type contentBlock struct {
	Type string `json:"type"` // "text" | "tool_use" | "tool_result"

	// type: "text"
	Text string `json:"text,omitempty"`

	// type: "tool_use" (in a model response)
	ID    string          `json:"id,omitempty"`
	Name  string          `json:"name,omitempty"`
	Input json.RawMessage `json:"input,omitempty"`

	// type: "tool_result" (in our follow-up request)
	ToolUseID string `json:"tool_use_id,omitempty"`
	Content   string `json:"content,omitempty"`
	IsError   bool   `json:"is_error,omitempty"`
}

func textBlock(s string) contentBlock { return contentBlock{Type: "text", Text: s} }

// chatMessage mirrors the {role, content} shape the API expects. role is
// "user" or "assistant".
type chatMessage struct {
	Role    string         `json:"role"`
	Content []contentBlock `json:"content"`
}

type anthropicRequest struct {
	Model     string        `json:"model"`
	MaxTokens int           `json:"max_tokens"`
	System    string        `json:"system"`
	Messages  []chatMessage `json:"messages"`
	Tools     []toolDef     `json:"tools,omitempty"`
}

type anthropicResponse struct {
	Content    []contentBlock `json:"content"`
	StopReason string         `json:"stop_reason"`
	Error      *struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error"`
}

// complete sends the system prompt + conversation (+ tools, if any) and
// returns the model's raw content blocks so the caller can tell a plain-text
// answer apart from a tool_use request and drive the tool loop.
func (a *anthropicClient) complete(ctx context.Context, system string, tools []toolDef, msgs []chatMessage) (anthropicResponse, error) {
	reqBody := anthropicRequest{
		Model:     a.model,
		MaxTokens: 1024,
		System:    system,
		Messages:  msgs,
		Tools:     tools,
	}
	raw, err := json.Marshal(reqBody)
	if err != nil {
		return anthropicResponse{}, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.anthropic.com/v1/messages", bytes.NewReader(raw))
	if err != nil {
		return anthropicResponse{}, err
	}
	req.Header.Set("content-type", "application/json")
	req.Header.Set("x-api-key", a.apiKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	resp, err := a.http.Do(req)
	if err != nil {
		return anthropicResponse{}, err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	var parsed anthropicResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return anthropicResponse{}, fmt.Errorf("assistant: bad LLM response (%d): %s", resp.StatusCode, truncate(string(body), 200))
	}
	if parsed.Error != nil {
		return anthropicResponse{}, fmt.Errorf("assistant: LLM error: %s", parsed.Error.Message)
	}
	if resp.StatusCode != http.StatusOK || len(parsed.Content) == 0 {
		return anthropicResponse{}, fmt.Errorf("assistant: LLM HTTP %d", resp.StatusCode)
	}
	return parsed, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
