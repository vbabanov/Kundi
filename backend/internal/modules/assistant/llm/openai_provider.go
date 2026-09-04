package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

const (
	maxProviderResponseBytes         int64 = 1 << 20
	defaultCompletionTokenBudget           = 700
	qwenMinimumCompletionTokenBudget       = 96
	DefaultPrimaryTimeout                  = 10 * time.Second
	DefaultFallbackTimeout                 = 8 * time.Second
	DefaultTotalTimeout                    = 12 * time.Second
)

// OpenAICompatibleProvider implements the bounded text-only Alem chat contract.
type OpenAICompatibleProvider struct {
	baseURL  string
	apiKey   string
	model    string
	provider string
	client   *http.Client
}

func NewOpenAICompatibleProvider(baseURL, apiKey, model string, timeout time.Duration) *OpenAICompatibleProvider {
	if timeout <= 0 {
		timeout = 12 * time.Second
	}
	return &OpenAICompatibleProvider{
		baseURL:  strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		apiKey:   strings.TrimSpace(apiKey),
		model:    strings.TrimSpace(model),
		provider: "alem",
		client:   &http.Client{Timeout: timeout},
	}
}

func (p *OpenAICompatibleProvider) Generate(ctx context.Context, req Request) (Response, error) {
	if p.baseURL == "" || p.apiKey == "" || p.model == "" {
		return Response{}, &ProviderError{Kind: ErrorConfiguration, Err: errors.New("Alem provider configuration is incomplete")}
	}
	payload := map[string]any{
		"model": p.model,
		"messages": []map[string]string{
			{"role": "system", "content": "You are Kundi, a safe learning assistant. Follow the supplied tutoring policy exactly."},
			{"role": "user", "content": req.Prompt},
		},
		"temperature": 0.2,
		"max_tokens":  completionTokenBudget(p.model),
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return Response{}, err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, chatCompletionsURL(p.baseURL), bytes.NewReader(body))
	if err != nil {
		return Response{}, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+p.apiKey)
	httpReq.Header.Set("Content-Type", "application/json")

	httpResp, err := p.client.Do(httpReq)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return Response{}, &ProviderError{Kind: ErrorTimeout, Err: context.DeadlineExceeded}
		}
		var netErr net.Error
		if errors.As(err, &netErr) {
			return Response{}, &ProviderError{Kind: ErrorUnavailable, Err: errors.New("provider network failure")}
		}
		return Response{}, &ProviderError{Kind: ErrorUnavailable, Err: errors.New("provider request failure")}
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode >= http.StatusBadRequest {
		kind := ErrorClient
		switch {
		case httpResp.StatusCode == http.StatusTooManyRequests:
			kind = ErrorRateLimit
		case httpResp.StatusCode >= http.StatusInternalServerError:
			kind = ErrorServer
		}
		_, _ = io.Copy(io.Discard, io.LimitReader(httpResp.Body, maxProviderResponseBytes))
		return Response{}, &ProviderError{Kind: kind, StatusCode: httpResp.StatusCode}
	}

	var decoded struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	decoder := json.NewDecoder(io.LimitReader(httpResp.Body, maxProviderResponseBytes))
	if err := decoder.Decode(&decoded); err != nil {
		return Response{}, &ProviderError{Kind: ErrorMalformed, Err: fmt.Errorf("decode provider response: %w", err)}
	}
	if len(decoded.Choices) == 0 || strings.TrimSpace(decoded.Choices[0].Message.Content) == "" {
		return Response{}, &ProviderError{Kind: ErrorMalformed, Err: errors.New("provider response content is empty")}
	}
	return Response{
		Text:     strings.TrimSpace(decoded.Choices[0].Message.Content),
		Provider: p.provider,
		Model:    p.model,
	}, nil
}

func chatCompletionsURL(configured string) string {
	value := strings.TrimRight(strings.TrimSpace(configured), "/")
	if strings.HasSuffix(strings.ToLower(value), "/chat/completions") {
		return value
	}
	return value + "/chat/completions"
}

// FallbackProvider calls the fallback exactly once and only for retryable
// availability failures. Client, rate-limit, malformed and policy errors do not fall back.
type FallbackProvider struct {
	primary  Provider
	fallback Provider
	policy   FallbackPolicy
}

type FallbackPolicy struct {
	PrimaryTimeout  time.Duration
	FallbackTimeout time.Duration
	TotalTimeout    time.Duration
}

func NewFallbackProvider(primary, fallback Provider) Provider {
	return NewFallbackProviderWithPolicy(primary, fallback, FallbackPolicy{})
}

func NewFallbackProviderWithPolicy(primary, fallback Provider, policy FallbackPolicy) Provider {
	if fallback == nil {
		return primary
	}
	return &FallbackProvider{primary: primary, fallback: fallback, policy: normalizedFallbackPolicy(policy)}
}

func (p *FallbackProvider) Generate(ctx context.Context, req Request) (Response, error) {
	totalCtx, cancelTotal := context.WithTimeout(ctx, p.policy.TotalTimeout)
	defer cancelTotal()

	primaryCtx, cancelPrimary := context.WithTimeout(totalCtx, p.policy.PrimaryTimeout)
	response, err := p.primary.Generate(primaryCtx, req)
	primaryContextErr := primaryCtx.Err()
	cancelPrimary()
	if err == nil || !isFallbackEligible(err) {
		if primaryContextErr != nil {
			return Response{}, timeoutError()
		}
		return response, err
	}
	if primaryContextErr != nil || isProviderErrorKind(err, ErrorTimeout) {
		return Response{}, timeoutError()
	}
	if totalCtx.Err() != nil {
		return Response{}, timeoutError()
	}

	fallbackCtx, cancelFallback := context.WithTimeout(totalCtx, p.policy.FallbackTimeout)
	response, err = p.fallback.Generate(fallbackCtx, req)
	fallbackContextErr := fallbackCtx.Err()
	cancelFallback()
	if fallbackContextErr != nil {
		return Response{}, timeoutError()
	}
	return response, err
}

func isFallbackEligible(err error) bool {
	var providerErr *ProviderError
	if !errors.As(err, &providerErr) {
		return false
	}
	switch providerErr.Kind {
	case ErrorServer, ErrorUnavailable:
		return true
	default:
		return false
	}
}

func normalizedFallbackPolicy(policy FallbackPolicy) FallbackPolicy {
	if policy.PrimaryTimeout <= 0 {
		policy.PrimaryTimeout = DefaultPrimaryTimeout
	}
	if policy.FallbackTimeout <= 0 {
		policy.FallbackTimeout = DefaultFallbackTimeout
	}
	if policy.TotalTimeout <= 0 {
		policy.TotalTimeout = DefaultTotalTimeout
	}
	return policy
}

func isProviderErrorKind(err error, kind ErrorKind) bool {
	var providerErr *ProviderError
	return errors.As(err, &providerErr) && providerErr.Kind == kind
}

func timeoutError() error {
	return &ProviderError{Kind: ErrorTimeout, Err: context.DeadlineExceeded}
}

func completionTokenBudget(model string) int {
	budget := defaultCompletionTokenBudget
	if strings.EqualFold(strings.TrimSpace(model), "qwen3-8") && budget < qwenMinimumCompletionTokenBudget {
		return qwenMinimumCompletionTokenBudget
	}
	return budget
}
