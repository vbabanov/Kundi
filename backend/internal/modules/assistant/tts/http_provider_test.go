package tts

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHTTPProviderRender(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/render" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"audio_url":"https://tts.local/audio/1.mp3"}`))
	}))
	defer server.Close()

	provider := NewHTTPProvider(server.URL, "api-key")
	audioURL, err := provider.Render(context.Background(), "hello")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if audioURL != "https://tts.local/audio/1.mp3" {
		t.Fatalf("unexpected audio URL: %s", audioURL)
	}
}
