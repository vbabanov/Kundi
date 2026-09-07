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
	maxProviderTokenCount                  = 10_000_000
	defaultCompletionTokenBudget           = 700
	gemmaCompletionTokenBudget             = 1400
	qwenMinimumCompletionTokenBudget       = 96
	DefaultPrimaryTimeout                  = 25 * time.Second
	DefaultFallbackTimeout                 = 8 * time.Second
	DefaultTotalTimeout                    = 28 * time.Second
)

// OpenAICompatibleProvider implements the bounded text-only Alem chat contract.
type OpenAICompatibleProvider struct {
	baseURL  string
	apiKey   string
	model    string
	provider string
	stage    ExecutionStage
	client   *http.Client
}

func NewOpenAICompatibleProvider(baseURL, apiKey, model string, timeout time.Duration) *OpenAICompatibleProvider {
	return NewOpenAICompatibleProviderForStage(baseURL, apiKey, model, timeout, StagePrimary)
}

func NewOpenAICompatibleProviderForStage(baseURL, apiKey, model string, timeout time.Duration, stage ExecutionStage) *OpenAICompatibleProvider {
	if timeout <= 0 {
		timeout = DefaultPrimaryTimeout
	}
	return &OpenAICompatibleProvider{
		baseURL:  strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		apiKey:   strings.TrimSpace(apiKey),
		model:    strings.TrimSpace(model),
		provider: "alem",
		stage:    normalizedStage(stage),
		client:   &http.Client{Timeout: timeout},
	}
}

func (p *OpenAICompatibleProvider) Generate(ctx context.Context, req Request) (response Response, retErr error) {
	startedAt := time.Now()
	response = newResponseMetadata(p.provider, p.model, p.stage)
	defer func() { addAttempt(&response, startedAt, retErr) }()
	if p.baseURL == "" || p.apiKey == "" || p.model == "" {
		return response, &ProviderError{Kind: ErrorConfiguration, Err: errors.New("Alem provider configuration is incomplete")}
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
		return response, err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, chatCompletionsURL(p.baseURL), bytes.NewReader(body))
	if err != nil {
		return response, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+p.apiKey)
	httpReq.Header.Set("Content-Type", "application/json")

	httpResp, err := p.client.Do(httpReq)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) || ctx.Err() != nil {
			cause := ctx.Err()
			if cause == nil {
				cause = context.DeadlineExceeded
			}
			return response, &ProviderError{Kind: ErrorTimeout, Err: cause}
		}
		var netErr net.Error
		if errors.As(err, &netErr) {
			return response, &ProviderError{Kind: ErrorUnavailable, Err: errors.New("provider network failure")}
		}
		return response, &ProviderError{Kind: ErrorUnavailable, Err: errors.New("provider request failure")}
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
		return response, &ProviderError{Kind: kind, StatusCode: httpResp.StatusCode}
	}

	var decoded struct {
		Choices []struct {
			Message struct {
				Content          string          `json:"content"`
				ReasoningContent json.RawMessage `json:"reasoning_content"`
			} `json:"message"`
			FinishReason string `json:"finish_reason"`
		} `json:"choices"`
		Usage struct {
			PromptTokens     int `json:"prompt_tokens"`
			CompletionTokens int `json:"completion_tokens"`
		} `json:"usage"`
	}
	responseBody, err := io.ReadAll(io.LimitReader(httpResp.Body, maxProviderResponseBytes+1))
	if err != nil {
		return response, &ProviderError{Kind: ErrorMalformed, Err: errors.New("read provider response")}
	}
	if int64(len(responseBody)) > maxProviderResponseBytes {
		return response, &ProviderError{Kind: ErrorMalformed, Err: errors.New("provider response exceeds size limit")}
	}
	if err := json.Unmarshal(responseBody, &decoded); err != nil {
		return response, &ProviderError{Kind: ErrorMalformed, Err: fmt.Errorf("decode provider response: %w", err)}
	}
	response.PromptTokens = boundedTokenCount(decoded.Usage.PromptTokens)
	response.CompletionTokens = boundedTokenCount(decoded.Usage.CompletionTokens)
	if len(decoded.Choices) == 0 {
		return response, &ProviderError{Kind: ErrorMalformed, Err: errors.New("provider response choices are empty")}
	}
	response.FinishReason = classifyFinishReason(decoded.Choices[0].FinishReason)
	if response.FinishReason == FinishReasonLength {
		return response, &ProviderError{Kind: ErrorIncomplete, Err: errors.New("provider response is incomplete")}
	}
	if response.FinishReason != FinishReasonStop {
		return response, &ProviderError{Kind: ErrorMalformed, Err: errors.New("provider response finish reason is invalid")}
	}
	content := strings.TrimSpace(decoded.Choices[0].Message.Content)
	if content == "" {
		return response, &ProviderError{Kind: ErrorMalformed, Err: errors.New("provider response content is empty")}
	}
	response.Text = content
	return response, nil
}

func classifyFinishReason(raw string) FinishReason {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "stop":
		return FinishReasonStop
	case "length":
		return FinishReasonLength
	case "":
		return FinishReasonMissing
	default:
		return FinishReasonOther
	}
}

func boundedTokenCount(value int) int {
	if value < 0 {
		return 0
	}
	if value > maxProviderTokenCount {
		return maxProviderTokenCount
	}
	return value
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
	response = withExecutionStage(response, StagePrimary)
	primaryContextErr := primaryCtx.Err()
	cancelPrimary()
	if err == nil || !isFallbackEligible(err) {
		if primaryContextErr != nil {
			return response, timeoutError()
		}
		return response, err
	}
	primaryResponse := response
	primaryErrorKind := providerErrorKind(err)
	if primaryContextErr != nil || isProviderErrorKind(err, ErrorTimeout) {
		return primaryResponse, timeoutError()
	}
	if totalCtx.Err() != nil {
		primaryResponse.PrimaryErrorKind = primaryErrorKind
		return primaryResponse, timeoutError()
	}

	fallbackCtx, cancelFallback := context.WithTimeout(totalCtx, p.policy.FallbackTimeout)
	fallbackResponse, fallbackErr := p.fallback.Generate(fallbackCtx, req)
	fallbackResponse = withExecutionStage(fallbackResponse, StageFallback)
	fallbackResponse.Attempts = append(primaryResponse.Attempts, fallbackResponse.Attempts...)
	if len(fallbackResponse.Attempts) > 2 {
		fallbackResponse.Attempts = fallbackResponse.Attempts[:2]
	}
	fallbackResponse.FallbackAttempted = true
	fallbackResponse.FallbackSucceeded = fallbackErr == nil && strings.TrimSpace(fallbackResponse.Text) != ""
	fallbackResponse.PrimaryErrorKind = primaryErrorKind
	fallbackContextErr := fallbackCtx.Err()
	cancelFallback()
	if fallbackContextErr != nil {
		return fallbackResponse, timeoutError()
	}
	return fallbackResponse, fallbackErr
}

func withExecutionStage(response Response, stage ExecutionStage) Response {
	response.Stage = normalizedStage(stage)
	for i := range response.Attempts {
		response.Attempts[i].Stage = response.Stage
	}
	return response
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
	if strings.EqualFold(strings.TrimSpace(model), "gemma4") {
		return gemmaCompletionTokenBudget
	}
	budget := defaultCompletionTokenBudget
	if strings.EqualFold(strings.TrimSpace(model), "qwen3-8") && budget < qwenMinimumCompletionTokenBudget {
		return qwenMinimumCompletionTokenBudget
	}
	return budget
}
