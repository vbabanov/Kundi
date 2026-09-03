package llm

import (
	"context"
	"errors"
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

func TestHTTPProviderClassifiesFailures(t *testing.T) {
	tests := []struct {
		name       string
		statusCode int
		body       string
		kind       ErrorKind
	}{
		{name: "provider 4xx", statusCode: http.StatusBadRequest, body: `{}`, kind: ErrorClient},
		{name: "provider 5xx", statusCode: http.StatusServiceUnavailable, body: `{}`, kind: ErrorServer},
		{name: "malformed JSON", statusCode: http.StatusOK, body: `{`, kind: ErrorMalformed},
		{name: "empty response", statusCode: http.StatusOK, body: `{"text":" "}`, kind: ErrorMalformed},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(test.statusCode)
				_, _ = w.Write([]byte(test.body))
			}))
			defer server.Close()

			_, err := NewHTTPProvider(server.URL, "api-key").Generate(context.Background(), Request{Prompt: "prompt"})
			var providerErr *ProviderError
			if !errors.As(err, &providerErr) || providerErr.Kind != test.kind {
				t.Fatalf("expected %s, got %#v", test.kind, err)
			}
		})
	}
}
