package app

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	assistantllm "github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/platform/config"
)

func TestResolveAssistantLLMProviderUsesSeparateKeys(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var request struct {
			Model string `json:"model"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		switch request.Model {
		case "primary-model":
			if r.Header.Get("Authorization") != "Bearer primary-test-key" {
				t.Fatal("primary request used the wrong credential")
			}
			w.WriteHeader(http.StatusServiceUnavailable)
		case "fallback-model":
			if r.Header.Get("Authorization") != "Bearer fallback-test-key" {
				t.Fatal("fallback request used the wrong credential")
			}
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"fallback ok"},"finish_reason":"stop"}]}`))
		default:
			t.Fatalf("unexpected model %q", request.Model)
		}
	}))
	defer server.Close()

	provider := resolveAssistantLLMProvider(config.AIConfig{
		AlemBaseURL:              server.URL + "/v1",
		AlemPrimaryAPIKey:        "primary-test-key",
		AlemFallbackAPIKey:       "fallback-test-key",
		AlemPrimaryModel:         "primary-model",
		AlemFallbackModel:        "fallback-model",
		AssistantPrimaryTimeout:  2 * time.Second,
		AssistantFallbackTimeout: 2 * time.Second,
		AssistantLLMTimeout:      3 * time.Second,
	})
	response, err := provider.Generate(context.Background(), assistantllm.Request{Prompt: "synthetic"})
	if err != nil || response.Text != "fallback ok" || response.Model != "fallback-model" {
		t.Fatalf("unexpected fallback response=%#v err=%v", response, err)
	}
}

func TestResolveAssistantLLMProviderUsesPrimaryOnlyWhenFallbackPairIsBlank(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if r.Header.Get("Authorization") != "Bearer primary-test-key" {
			t.Fatal("primary credential was not used")
		}
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"primary ok"},"finish_reason":"stop"}]}`))
	}))
	defer server.Close()

	provider := resolveAssistantLLMProvider(config.AIConfig{
		AlemBaseURL:             server.URL + "/v1",
		AlemPrimaryAPIKey:       "primary-test-key",
		AlemPrimaryModel:        "gemma4",
		AssistantPrimaryTimeout: time.Second,
	})
	response, err := provider.Generate(context.Background(), assistantllm.Request{Prompt: "synthetic"})
	if err != nil || response.Text != "primary ok" || response.Model != "gemma4" || response.Stage != assistantllm.StagePrimary || requests != 1 || response.FallbackAttempted {
		t.Fatalf("unexpected primary response=%#v err=%v", response, err)
	}
}
