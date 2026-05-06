package whatsapp

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"mime"
	"net/http"
	"os"
	"path/filepath"
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
			Timeout: 10 * time.Second,
		},
	}
}

func (p *HTTPProvider) Send(ctx context.Context, req ProviderRequest) (ProviderResult, error) {
	if p.baseURL == "" {
		return ProviderResult{}, fmt.Errorf("whatsapp base URL is required for http provider")
	}
	requestPayload := map[string]any{
		"dispatch_type": req.DispatchType,
		"student_id":    req.StudentID,
		"text":          req.Text,
		"object_key":    req.ObjectKey,
		"file_name":     req.FileName,
		"metadata":      req.Metadata,
	}
	if mediaPath, ok := mediaObjectPath(req.ObjectKey); ok {
		mediaBytes, readErr := os.ReadFile(mediaPath)
		if readErr != nil {
			if os.IsNotExist(readErr) {
				return ProviderResult{}, ErrMediaObjectNotFound
			}
			return ProviderResult{}, fmt.Errorf("read media object: %w", readErr)
		}
		mediaName := strings.TrimSpace(req.FileName)
		if mediaName == "" {
			mediaName = filepath.Base(mediaPath)
		}
		requestPayload["media_base64"] = base64.StdEncoding.EncodeToString(mediaBytes)
		requestPayload["media_file_name"] = mediaName
		requestPayload["media_mime_type"] = detectMediaMIMEType(mediaName)
	}
	body, err := json.Marshal(requestPayload)
	if err != nil {
		return ProviderResult{}, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, p.baseURL+"/dispatch", bytes.NewReader(body))
	if err != nil {
		return ProviderResult{}, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	if p.apiKey != "" {
		httpReq.Header.Set("Authorization", "Bearer "+p.apiKey)
	}

	resp, err := p.client.Do(httpReq)
	if err != nil {
		return ProviderResult{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return ProviderResult{}, fmt.Errorf("whatsapp provider returned status %d", resp.StatusCode)
	}

	var providerResponse struct {
		ExternalMessageID string `json:"external_message_id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&providerResponse); err != nil {
		return ProviderResult{}, err
	}
	if strings.TrimSpace(providerResponse.ExternalMessageID) == "" {
		return ProviderResult{}, fmt.Errorf("whatsapp provider returned empty external_message_id")
	}
	return ProviderResult{ExternalMessageID: strings.TrimSpace(providerResponse.ExternalMessageID)}, nil
}

func detectMediaMIMEType(fileName string) string {
	ext := strings.ToLower(strings.TrimSpace(filepath.Ext(fileName)))
	if ext == "" {
		return "image/jpeg"
	}
	if guessed := strings.TrimSpace(mime.TypeByExtension(ext)); guessed != "" {
		return guessed
	}
	return "image/jpeg"
}
