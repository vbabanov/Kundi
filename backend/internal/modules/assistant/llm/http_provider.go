package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type HTTPProvider struct {
	baseURL string
	apiKey  string
	client  *http.Client
}

func NewHTTPProvider(baseURL string, apiKey string) *HTTPProvider {
	return &HTTPProvider{
		baseURL: strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		apiKey:  strings.TrimSpace(apiKey),
		client: &http.Client{
			Timeout: 12 * time.Second,
		},
	}
}

func (p *HTTPProvider) Generate(ctx context.Context, req Request) (Response, error) {
	if p.baseURL == "" {
		return Response{}, fmt.Errorf("llm base URL is required for http provider")
	}
	body, err := json.Marshal(map[string]any{
		"mode":         req.Mode,
		"prompt":       req.Prompt,
		"persona_tone": req.PersonaTone,
		"style":        req.Style,
		"history":      req.History,
	})
	if err != nil {
		return Response{}, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, p.baseURL+"/generate", bytes.NewReader(body))
	if err != nil {
		return Response{}, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	if p.apiKey != "" {
		httpReq.Header.Set("Authorization", "Bearer "+p.apiKey)
	}

	httpResp, err := p.client.Do(httpReq)
	if err != nil {
		return Response{}, err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode >= 400 {
		return Response{}, fmt.Errorf("llm provider returned status %d", httpResp.StatusCode)
	}

	var payload struct {
		Text string `json:"text"`
	}
	if err := json.NewDecoder(httpResp.Body).Decode(&payload); err != nil {
		return Response{}, err
	}
	if strings.TrimSpace(payload.Text) == "" {
		return Response{}, fmt.Errorf("llm response text is empty")
	}
	return Response{Text: strings.TrimSpace(payload.Text)}, nil
}
