package llm

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHTTPProviderGenerate(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/generate" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"text":"provider-answer"}`))
	}))
	defer server.Close()

	provider := NewHTTPProvider(server.URL, "api-key")
	resp, err := provider.Generate(context.Background(), Request{
		Mode:        "tutor",
		Prompt:      "prompt",
		PersonaTone: "mentor",
		Style:       "step_by_step",
		History:     []string{"a", "b"},
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if resp.Text != "provider-answer" {
		t.Fatalf("unexpected response text: %s", resp.Text)
	}
}
