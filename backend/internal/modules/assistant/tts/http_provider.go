package tts

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

func (p *HTTPProvider) Render(ctx context.Context, text string) (string, error) {
	if p.baseURL == "" {
		return "", fmt.Errorf("tts base URL is required for http provider")
	}
	if strings.TrimSpace(text) == "" {
		return "", nil
	}

	body, err := json.Marshal(map[string]any{"text": strings.TrimSpace(text)})
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.baseURL+"/render", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if p.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+p.apiKey)
	}

	resp, err := p.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("tts provider returned status %d", resp.StatusCode)
	}

	var payload struct {
		AudioURL string `json:"audio_url"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return "", err
	}
	return strings.TrimSpace(payload.AudioURL), nil
}
