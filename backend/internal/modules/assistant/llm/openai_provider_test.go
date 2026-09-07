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
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"  safe answer  "},"finish_reason":"stop"}],"usage":{"prompt_tokens":17,"completion_tokens":9}}`))
	}))
	defer server.Close()

	provider := NewOpenAICompatibleProvider(server.URL+"/v1", "test-key", "exact-model-id", time.Second)
	response, err := provider.Generate(context.Background(), Request{Prompt: "question"})
	if err != nil || response.Text != "safe answer" || response.Model != "exact-model-id" || response.Provider != "alem" ||
		response.Stage != StagePrimary || response.FinishReason != FinishReasonStop || response.PromptTokens != 17 || response.CompletionTokens != 9 {
		t.Fatalf("unexpected response=%#v err=%v", response, err)
	}
	if len(response.Attempts) != 1 || response.Attempts[0].ErrorKind != "" || response.Attempts[0].Stage != StagePrimary {
		t.Fatalf("unexpected attempts=%#v", response.Attempts)
	}
}

func TestOpenAICompatibleProviderAcceptsFullChatCompletionsURL(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected request path=%s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}`))
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
		{"incomplete", &ProviderError{Kind: ErrorIncomplete}, false},
		{"configuration", &ProviderError{Kind: ErrorConfiguration}, false},
	}
	for _, item := range tests {
		t.Run(item.name, func(t *testing.T) {
			fallback := &scriptedProvider{response: providerTestResponse("qwen3-8", StageFallback, "fallback")}
			primaryResponse := providerTestResponse("gemma4", StagePrimary, "")
			primaryResponse.Attempts[0].ErrorKind = providerErrorKind(item.primaryError)
			provider := NewFallbackProviderWithPolicy(&scriptedProvider{response: primaryResponse, err: item.primaryError}, fallback, FallbackPolicy{
				PrimaryTimeout: time.Second, FallbackTimeout: time.Second, TotalTimeout: 2 * time.Second,
			})
			response, _ := provider.Generate(context.Background(), Request{Prompt: "q"})
			if (fallback.calls == 1) != item.wantFallback {
				t.Fatalf("fallback calls=%d", fallback.calls)
			}
			if response.FallbackAttempted != item.wantFallback || response.FallbackSucceeded != item.wantFallback {
				t.Fatalf("fallback markers attempted=%v succeeded=%v want=%v", response.FallbackAttempted, response.FallbackSucceeded, item.wantFallback)
			}
		})
	}
}

func TestFallbackProviderReturnsPrimarySuccessWithoutFallback(t *testing.T) {
	primary := &scriptedProvider{response: providerTestResponse("gemma4", StagePrimary, "primary")}
	fallback := &scriptedProvider{response: providerTestResponse("qwen3-8", StageFallback, "fallback")}
	provider := NewFallbackProviderWithPolicy(primary, fallback, FallbackPolicy{
		PrimaryTimeout: time.Second, FallbackTimeout: time.Second, TotalTimeout: 2 * time.Second,
	})
	response, err := provider.Generate(context.Background(), Request{Prompt: "q"})
	if err != nil || response.Text != "primary" || response.FallbackAttempted || response.FallbackSucceeded || primary.calls != 1 || fallback.calls != 0 {
		t.Fatalf("unexpected response=%#v err=%v primary=%d fallback=%d", response, err, primary.calls, fallback.calls)
	}
}

func TestFallbackProviderDoesNotCallFallbackAfterPrimaryTimeout(t *testing.T) {
	fallback := &scriptedProvider{response: providerTestResponse("qwen3-8", StageFallback, "must not run")}
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
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":""},"finish_reason":"stop"}]}`))
	}))
	defer server.Close()

	_, err := NewOpenAICompatibleProvider(server.URL, "key", "qwen3-8", time.Second).Generate(context.Background(), Request{Prompt: "q"})
	if !isProviderErrorKind(err, ErrorMalformed) {
		t.Fatalf("expected empty qwen content to be malformed, got %v", err)
	}
}

func TestGemmaUsesCanaryCompletionBudget(t *testing.T) {
	if gemmaCompletionTokenBudget != 1400 {
		t.Fatalf("Gemma completion budget=%d", gemmaCompletionTokenBudget)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var request struct {
			Model     string `json:"model"`
			MaxTokens int    `json:"max_tokens"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		if request.Model != "gemma4" || request.MaxTokens != gemmaCompletionTokenBudget {
			t.Fatalf("unexpected Gemma request model=%q max_tokens=%d", request.Model, request.MaxTokens)
		}
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"safe answer"},"finish_reason":"stop"}]}`))
	}))
	defer server.Close()

	response, err := NewOpenAICompatibleProvider(server.URL, "key", "gemma4", time.Second).Generate(context.Background(), Request{Prompt: "q"})
	if err != nil || response.Text != "safe answer" {
		t.Fatalf("unexpected response=%#v err=%v", response, err)
	}
}

func TestCanaryTimeoutDefaults(t *testing.T) {
	policy := normalizedFallbackPolicy(FallbackPolicy{})
	if DefaultPrimaryTimeout != 25*time.Second || policy.PrimaryTimeout != 25*time.Second {
		t.Fatalf("primary timeout default=%s policy=%s", DefaultPrimaryTimeout, policy.PrimaryTimeout)
	}
	if DefaultTotalTimeout != 28*time.Second || policy.TotalTimeout != 28*time.Second {
		t.Fatalf("total timeout default=%s policy=%s", DefaultTotalTimeout, policy.TotalTimeout)
	}
	if DefaultFallbackTimeout != 8*time.Second || policy.FallbackTimeout != 8*time.Second {
		t.Fatalf("fallback timeout changed: default=%s policy=%s", DefaultFallbackTimeout, policy.FallbackTimeout)
	}

	provider := NewOpenAICompatibleProvider("https://example.invalid", "key", "gemma4", 0)
	if provider.client.Timeout != 25*time.Second {
		t.Fatalf("provider default timeout=%s", provider.client.Timeout)
	}
}

func TestOpenAICompatibleProviderResponseContract(t *testing.T) {
	tests := []struct {
		name       string
		body       string
		wantText   string
		wantFinish FinishReason
		wantKind   ErrorKind
	}{
		{name: "stop with content", body: `{"choices":[{"message":{"content":" answer "},"finish_reason":"stop"}]}`, wantText: "answer", wantFinish: FinishReasonStop},
		{name: "length with content", body: `{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}`, wantFinish: FinishReasonLength, wantKind: ErrorIncomplete},
		{name: "length with empty content uses incomplete precedence", body: `{"choices":[{"message":{"content":""},"finish_reason":"length"}]}`, wantFinish: FinishReasonLength, wantKind: ErrorIncomplete},
		{name: "stop with empty content", body: `{"choices":[{"message":{"content":""},"finish_reason":"stop"}]}`, wantFinish: FinishReasonStop, wantKind: ErrorMalformed},
		{name: "missing choices", body: `{"choices":[]}`, wantFinish: FinishReasonMissing, wantKind: ErrorMalformed},
		{name: "missing finish reason", body: `{"choices":[{"message":{"content":"answer"}}]}`, wantFinish: FinishReasonMissing, wantKind: ErrorMalformed},
		{name: "unknown finish reason", body: `{"choices":[{"message":{"content":"answer"},"finish_reason":"tool_calls"}]}`, wantFinish: FinishReasonOther, wantKind: ErrorMalformed},
		{name: "reasoning is not answer", body: `{"choices":[{"message":{"content":"","reasoning_content":"private reasoning"},"finish_reason":"stop"}]}`, wantFinish: FinishReasonStop, wantKind: ErrorMalformed},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(test.body))
			}))
			defer server.Close()

			response, err := NewOpenAICompatibleProvider(server.URL, "key", "gemma4", time.Second).Generate(context.Background(), Request{Prompt: "q"})
			if test.wantKind == "" {
				if err != nil || response.Text != test.wantText {
					t.Fatalf("response=%#v err=%v", response, err)
				}
			} else {
				if !isProviderErrorKind(err, test.wantKind) || response.Text != "" {
					t.Fatalf("response=%#v err=%v want_kind=%s", response, err, test.wantKind)
				}
			}
			if response.FinishReason != test.wantFinish || response.Provider != "alem" || response.Model != "gemma4" || response.Stage != StagePrimary {
				t.Fatalf("metadata=%#v", response)
			}
		})
	}
}

func TestOpenAICompatibleProviderBoundsResponseBodyAndUsage(t *testing.T) {
	t.Run("response body", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(strings.Repeat("x", int(maxProviderResponseBytes)+1)))
		}))
		defer server.Close()
		response, err := NewOpenAICompatibleProvider(server.URL, "key", "gemma4", time.Second).Generate(context.Background(), Request{Prompt: "q"})
		if !isProviderErrorKind(err, ErrorMalformed) || response.Provider != "alem" || response.Model != "gemma4" {
			t.Fatalf("response=%#v err=%v", response, err)
		}
	})
	t.Run("usage", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":-4,"completion_tokens":999999999}}`))
		}))
		defer server.Close()
		response, err := NewOpenAICompatibleProvider(server.URL, "key", "gemma4", time.Second).Generate(context.Background(), Request{Prompt: "q"})
		if err != nil || response.PromptTokens != 0 || response.CompletionTokens != maxProviderTokenCount {
			t.Fatalf("response=%#v err=%v", response, err)
		}
	})
}

func TestOpenAICompatibleProviderPreservesFailureAttribution(t *testing.T) {
	t.Run("429", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusTooManyRequests) }))
		defer server.Close()
		response, err := NewOpenAICompatibleProvider(server.URL, "key", "gemma4", time.Second).Generate(context.Background(), Request{Prompt: "q"})
		assertProviderFailureMetadata(t, response, err, ErrorRateLimit, "gemma4", StagePrimary)
	})
	t.Run("timeout", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { time.Sleep(50 * time.Millisecond) }))
		defer server.Close()
		response, err := NewOpenAICompatibleProvider(server.URL, "key", "gemma4", 5*time.Millisecond).Generate(context.Background(), Request{Prompt: "q"})
		assertProviderFailureMetadata(t, response, err, ErrorTimeout, "gemma4", StagePrimary)
	})
	t.Run("cancellation", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
		defer server.Close()
		ctx, cancel := context.WithCancel(context.Background())
		cancel()
		response, err := NewOpenAICompatibleProvider(server.URL, "key", "gemma4", time.Second).Generate(ctx, Request{Prompt: "q"})
		assertProviderFailureMetadata(t, response, err, ErrorTimeout, "gemma4", StagePrimary)
	})
}

func TestFallbackProviderPreservesTerminalAttribution(t *testing.T) {
	tests := []struct {
		name           string
		primaryKind    ErrorKind
		fallbackBody   string
		fallbackStatus int
		wantKind       ErrorKind
		wantSuccess    bool
	}{
		{name: "primary 5xx fallback success", primaryKind: ErrorServer, fallbackBody: `{"choices":[{"message":{"content":"fallback"},"finish_reason":"stop"}]}`, wantSuccess: true},
		{name: "primary 5xx fallback length", primaryKind: ErrorServer, fallbackBody: `{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}`, wantKind: ErrorIncomplete},
		{name: "primary unavailable fallback malformed", primaryKind: ErrorUnavailable, fallbackBody: `{"choices":[]}`, wantKind: ErrorMalformed},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			fallbackServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				if test.fallbackStatus != 0 {
					w.WriteHeader(test.fallbackStatus)
				}
				_, _ = w.Write([]byte(test.fallbackBody))
			}))
			defer fallbackServer.Close()
			primaryResponse := providerTestResponse("gemma4", StagePrimary, "")
			primaryResponse.Attempts[0].ErrorKind = test.primaryKind
			fallback := NewOpenAICompatibleProviderForStage(fallbackServer.URL, "key", "qwen3-8", time.Second, StageFallback)
			provider := NewFallbackProviderWithPolicy(&scriptedProvider{response: primaryResponse, err: &ProviderError{Kind: test.primaryKind}}, fallback, FallbackPolicy{
				PrimaryTimeout: time.Second, FallbackTimeout: time.Second, TotalTimeout: 2 * time.Second,
			})
			response, err := provider.Generate(context.Background(), Request{Prompt: "q"})
			if test.wantSuccess {
				if err != nil || response.Text != "fallback" {
					t.Fatalf("response=%#v err=%v", response, err)
				}
			} else if !isProviderErrorKind(err, test.wantKind) || response.Text != "" {
				t.Fatalf("response=%#v err=%v want_kind=%s", response, err, test.wantKind)
			}
			if !response.FallbackAttempted || response.FallbackSucceeded != test.wantSuccess || response.Provider != "alem" || response.Model != "qwen3-8" || response.Stage != StageFallback || response.PrimaryErrorKind != test.primaryKind {
				t.Fatalf("terminal metadata=%#v", response)
			}
			if len(response.Attempts) != 2 || response.Attempts[0].Stage != StagePrimary || response.Attempts[1].Stage != StageFallback {
				t.Fatalf("attempts=%#v", response.Attempts)
			}
		})
	}
}

func TestFallbackProviderPrimaryTimeoutRetainsMetadataAndSkipsFallback(t *testing.T) {
	primaryResponse := providerTestResponse("gemma4", StagePrimary, "")
	primaryResponse.Attempts[0].ErrorKind = ErrorTimeout
	fallback := &scriptedProvider{response: providerTestResponse("qwen3-8", StageFallback, "must not run")}
	provider := NewFallbackProviderWithPolicy(&scriptedProvider{response: primaryResponse, err: &ProviderError{Kind: ErrorTimeout}}, fallback, FallbackPolicy{
		PrimaryTimeout: time.Second, FallbackTimeout: time.Second, TotalTimeout: 2 * time.Second,
	})
	response, err := provider.Generate(context.Background(), Request{Prompt: "q"})
	assertProviderFailureMetadata(t, response, err, ErrorTimeout, "gemma4", StagePrimary)
	if fallback.calls != 0 || response.FallbackAttempted || response.FallbackSucceeded {
		t.Fatalf("unexpected fallback state response=%#v calls=%d", response, fallback.calls)
	}
}

func assertProviderFailureMetadata(t *testing.T, response Response, err error, kind ErrorKind, model string, stage ExecutionStage) {
	t.Helper()
	if !isProviderErrorKind(err, kind) || response.Provider != "alem" || response.Model != model || response.Stage != stage {
		t.Fatalf("response=%#v err=%v", response, err)
	}
	if len(response.Attempts) != 1 || response.Attempts[0].ErrorKind != kind || response.Attempts[0].Stage != stage {
		t.Fatalf("attempts=%#v", response.Attempts)
	}
}

func providerTestResponse(model string, stage ExecutionStage, text string) Response {
	response := Response{Text: text, Provider: "alem", Model: model, Stage: stage, FinishReason: FinishReasonStop}
	response.Attempts = []Attempt{{Provider: "alem", Model: model, Stage: stage, FinishReason: FinishReasonStop}}
	return response
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
