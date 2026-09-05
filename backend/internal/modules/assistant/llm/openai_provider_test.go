package llm

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestOpenAICompatibleProviderUsesChatCompletions(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" || r.Header.Get("Authorization") != "Bearer test-key" {
			t.Fatalf("unexpected request: path=%s auth=%s", r.URL.Path, r.Header.Get("Authorization"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"  safe answer  "}}]}`))
	}))
	defer server.Close()

	provider := NewOpenAICompatibleProvider(server.URL+"/v1", "test-key", "exact-model-id", time.Second)
	response, err := provider.Generate(context.Background(), Request{Prompt: "question"})
	if err != nil || response.Text != "safe answer" || response.Model != "exact-model-id" || response.Provider != "alem" {
		t.Fatalf("unexpected response=%#v err=%v", response, err)
	}
}

func TestOpenAICompatibleProviderAcceptsFullChatCompletionsURL(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected request path=%s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"ok"}}]}`))
	}))
	defer server.Close()

	provider := NewOpenAICompatibleProvider(server.URL+"/v1/chat/completions", "test-key", "exact-model-id", time.Second)
	response, err := provider.Generate(context.Background(), Request{Prompt: "question"})
	if err != nil || response.Text != "ok" {
		t.Fatalf("unexpected response=%#v err=%v", response, err)
	}
}

func TestFallbackProviderOnlyFallsBackForAvailabilityFailures(t *testing.T) {
	tests := []struct {
		name         string
		primaryError error
		wantFallback bool
	}{
		{"server", &ProviderError{Kind: ErrorServer}, true},
		{"unavailable", &ProviderError{Kind: ErrorUnavailable}, true},
		{"timeout", &ProviderError{Kind: ErrorTimeout}, false},
		{"rate limit", &ProviderError{Kind: ErrorRateLimit}, false},
		{"client", &ProviderError{Kind: ErrorClient}, false},
		{"malformed", &ProviderError{Kind: ErrorMalformed}, false},
		{"configuration", &ProviderError{Kind: ErrorConfiguration}, false},
	}
	for _, item := range tests {
		t.Run(item.name, func(t *testing.T) {
			fallback := &scriptedProvider{response: Response{Text: "fallback"}}
			provider := NewFallbackProviderWithPolicy(&scriptedProvider{err: item.primaryError}, fallback, FallbackPolicy{
				PrimaryTimeout: time.Second, FallbackTimeout: time.Second, TotalTimeout: 2 * time.Second,
			})
			response, _ := provider.Generate(context.Background(), Request{Prompt: "q"})
			if (fallback.calls == 1) != item.wantFallback {
				t.Fatalf("fallback calls=%d", fallback.calls)
			}
			if response.FallbackUsed != item.wantFallback {
				t.Fatalf("fallback telemetry marker=%v want=%v", response.FallbackUsed, item.wantFallback)
			}
		})
	}
}

func TestFallbackProviderReturnsPrimarySuccessWithoutFallback(t *testing.T) {
	primary := &scriptedProvider{response: Response{Text: "primary"}}
	fallback := &scriptedProvider{response: Response{Text: "fallback"}}
	provider := NewFallbackProviderWithPolicy(primary, fallback, FallbackPolicy{
		PrimaryTimeout: time.Second, FallbackTimeout: time.Second, TotalTimeout: 2 * time.Second,
	})
	response, err := provider.Generate(context.Background(), Request{Prompt: "q"})
	if err != nil || response.Text != "primary" || response.FallbackUsed || primary.calls != 1 || fallback.calls != 0 {
		t.Fatalf("unexpected response=%#v err=%v primary=%d fallback=%d", response, err, primary.calls, fallback.calls)
	}
}

func TestFallbackProviderDoesNotCallFallbackAfterPrimaryTimeout(t *testing.T) {
	fallback := &scriptedProvider{response: Response{Text: "must not run"}}
	provider := NewFallbackProviderWithPolicy(&blockingProvider{}, fallback, FallbackPolicy{
		PrimaryTimeout: 20 * time.Millisecond, FallbackTimeout: time.Second, TotalTimeout: 100 * time.Millisecond,
	})
	_, err := provider.Generate(context.Background(), Request{Prompt: "q"})
	if !isProviderErrorKind(err, ErrorTimeout) || fallback.calls != 0 {
		t.Fatalf("expected primary timeout without fallback, err=%v fallback=%d", err, fallback.calls)
	}
}

func TestFallbackProviderTotalDeadlineIsBounded(t *testing.T) {
	primary := &delayedProvider{delay: 20 * time.Millisecond, err: &ProviderError{Kind: ErrorServer}}
	fallback := &blockingProvider{}
	provider := NewFallbackProviderWithPolicy(primary, fallback, FallbackPolicy{
		PrimaryTimeout: 50 * time.Millisecond, FallbackTimeout: time.Second, TotalTimeout: 70 * time.Millisecond,
	})
	started := time.Now()
	_, err := provider.Generate(context.Background(), Request{Prompt: "q"})
	elapsed := time.Since(started)
	if !isProviderErrorKind(err, ErrorTimeout) || elapsed > 250*time.Millisecond {
		t.Fatalf("total deadline was not bounded: elapsed=%s err=%v", elapsed, err)
	}
}

func TestOpenAICompatibleProviderClassifies429AndMalformed(t *testing.T) {
	for _, item := range []struct {
		name   string
		status int
		body   string
		kind   ErrorKind
	}{
		{"rate", http.StatusTooManyRequests, `{}`, ErrorRateLimit},
		{"server", http.StatusServiceUnavailable, `{}`, ErrorServer},
		{"malformed", http.StatusOK, `{"choices":[]}`, ErrorMalformed},
	} {
		t.Run(item.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(item.status)
				_, _ = w.Write([]byte(item.body))
			}))
			defer server.Close()
			_, err := NewOpenAICompatibleProvider(server.URL, "key", "model", time.Second).Generate(context.Background(), Request{Prompt: "q"})
			if err == nil || !strings.Contains(err.Error(), string(item.kind)) {
				t.Fatalf("expected %s, got %v", item.kind, err)
			}
		})
	}
}

func TestQwenUsesMinimumCompletionBudgetAndRejectsEmptyContent(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var request struct {
			Model     string `json:"model"`
			MaxTokens int    `json:"max_tokens"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		if request.Model != "qwen3-8" || request.MaxTokens < qwenMinimumCompletionTokenBudget {
			t.Fatalf("unexpected qwen request model=%q max_tokens=%d", request.Model, request.MaxTokens)
		}
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":""}}]}`))
	}))
	defer server.Close()

	_, err := NewOpenAICompatibleProvider(server.URL, "key", "qwen3-8", time.Second).Generate(context.Background(), Request{Prompt: "q"})
	if !isProviderErrorKind(err, ErrorMalformed) {
		t.Fatalf("expected empty qwen content to be malformed, got %v", err)
	}
}

type scriptedProvider struct {
	response Response
	err      error
	calls    int
}

func (p *scriptedProvider) Generate(context.Context, Request) (Response, error) {
	p.calls++
	return p.response, p.err
}

type blockingProvider struct{}

func (p *blockingProvider) Generate(ctx context.Context, _ Request) (Response, error) {
	<-ctx.Done()
	return Response{}, &ProviderError{Kind: ErrorTimeout, Err: ctx.Err()}
}

type delayedProvider struct {
	delay time.Duration
	err   error
}

func (p *delayedProvider) Generate(ctx context.Context, _ Request) (Response, error) {
	timer := time.NewTimer(p.delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return Response{}, &ProviderError{Kind: ErrorTimeout, Err: ctx.Err()}
	case <-timer.C:
		return Response{}, p.err
	}
}
