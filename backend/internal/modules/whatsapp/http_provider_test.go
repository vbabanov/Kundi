package whatsapp

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestHTTPProviderSend(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/dispatch" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"external_message_id":"provider-123"}`))
	}))
	defer server.Close()

	provider := NewHTTPProvider(server.URL, "token")
	result, err := provider.Send(context.Background(), ProviderRequest{
		DispatchType: "homework_digest",
		StudentID:    "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		Text:         "digest text",
		Metadata:     map[string]any{"source": "test"},
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if result.ExternalMessageID != "provider-123" {
		t.Fatalf("unexpected external message id: %s", result.ExternalMessageID)
	}
}

func TestHTTPProviderSendWithMediaObject(t *testing.T) {
	var captured map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/dispatch" {
			http.NotFound(w, r)
			return
		}
		if err := json.NewDecoder(r.Body).Decode(&captured); err != nil {
			t.Fatalf("decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"external_message_id":"provider-media-123"}`))
	}))
	defer server.Close()

	tmpDir := t.TempDir()
	mediaPath := filepath.Join(tmpDir, "photo.jpg")
	if err := os.WriteFile(mediaPath, []byte("fake-jpeg-bytes"), 0o600); err != nil {
		t.Fatalf("write temp media: %v", err)
	}

	provider := NewHTTPProvider(server.URL, "token")
	result, err := provider.Send(context.Background(), ProviderRequest{
		DispatchType: "homework_photo",
		StudentID:    "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		Text:         "caption",
		ObjectKey:    "file://" + mediaPath,
		FileName:     "lesson-photo.jpg",
		Metadata:     map[string]any{"source": "test"},
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if result.ExternalMessageID != "provider-media-123" {
		t.Fatalf("unexpected external message id: %s", result.ExternalMessageID)
	}
	if captured == nil {
		t.Fatalf("expected captured payload")
	}
	if strings.TrimSpace(anyToString(captured["media_base64"])) == "" {
		t.Fatalf("expected media_base64 in payload")
	}
	if got := anyToString(captured["media_file_name"]); got != "lesson-photo.jpg" {
		t.Fatalf("expected media_file_name lesson-photo.jpg, got %s", got)
	}
}

func TestHTTPProviderSendReturnsMediaNotFound(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"external_message_id":"provider-123"}`))
	}))
	defer server.Close()

	provider := NewHTTPProvider(server.URL, "token")
	_, err := provider.Send(context.Background(), ProviderRequest{
		DispatchType: "homework_photo",
		StudentID:    "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		Text:         "caption",
		ObjectKey:    "file:///tmp/missing-photo.jpg",
		FileName:     "missing-photo.jpg",
		Metadata:     map[string]any{"source": "test"},
	})
	if err == nil {
		t.Fatalf("expected error")
	}
	if err != ErrMediaObjectNotFound {
		t.Fatalf("expected ErrMediaObjectNotFound, got %v", err)
	}
}

func anyToString(value any) string {
	if value == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprintf("%v", value))
}
