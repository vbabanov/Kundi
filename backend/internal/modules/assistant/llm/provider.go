package llm

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
)

type ErrorKind string

const (
	ErrorClient        ErrorKind = "provider_client_error"
	ErrorRateLimit     ErrorKind = "provider_rate_limit"
	ErrorServer        ErrorKind = "provider_server_error"
	ErrorUnavailable   ErrorKind = "provider_unavailable"
	ErrorTimeout       ErrorKind = "provider_timeout"
	ErrorMalformed     ErrorKind = "provider_malformed_response"
	ErrorIncomplete    ErrorKind = "provider_incomplete_response"
	ErrorConfiguration ErrorKind = "provider_configuration_error"
)

type ExecutionStage string

const (
	StageNone     ExecutionStage = "none"
	StagePrimary  ExecutionStage = "primary"
	StageFallback ExecutionStage = "fallback"
)

type FinishReason string

const (
	FinishReasonNone    FinishReason = "none"
	FinishReasonStop    FinishReason = "stop"
	FinishReasonLength  FinishReason = "length"
	FinishReasonMissing FinishReason = "missing"
	FinishReasonOther   FinishReason = "other"
)

type ProviderError struct {
	Kind       ErrorKind
	StatusCode int
	Err        error
}

func (e *ProviderError) Error() string {
	if e == nil {
		return ""
	}
	if e.StatusCode != 0 {
		return fmt.Sprintf("llm provider error (%s, status %d)", e.Kind, e.StatusCode)
	}
	return fmt.Sprintf("llm provider error (%s)", e.Kind)
}

func (e *ProviderError) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.Err
}

type Request struct {
	Mode        string
	Prompt      string
	PersonaTone string
	Style       string
	History     []string
}

type Response struct {
	Text              string
	Provider          string
	Model             string
	Stage             ExecutionStage
	FinishReason      FinishReason
	PromptTokens      int
	CompletionTokens  int
	FallbackAttempted bool
	FallbackSucceeded bool
	PrimaryErrorKind  ErrorKind
	Attempts          []Attempt
}

type Attempt struct {
	Provider     string
	Model        string
	Stage        ExecutionStage
	FinishReason FinishReason
	ErrorKind    ErrorKind
	LatencyMS    float64
}

type Provider interface {
	Generate(ctx context.Context, req Request) (Response, error)
}

type DeterministicProvider struct{}

func NewDeterministicProvider() *DeterministicProvider {
	return &DeterministicProvider{}
}

func (p *DeterministicProvider) Generate(_ context.Context, req Request) (response Response, retErr error) {
	startedAt := time.Now()
	response = newResponseMetadata("deterministic", "deterministic", StagePrimary)
	defer func() { addAttempt(&response, startedAt, retErr) }()
	prompt := strings.TrimSpace(req.Prompt)
	if prompt == "" {
		return response, errors.New("empty prompt")
	}
	if strings.Contains(strings.ToLower(prompt), "[llm:fail]") {
		return response, errors.New("forced llm failure")
	}
	response.Text = "[" + req.Mode + "|" + req.PersonaTone + "|" + req.Style + "] " + prompt
	response.FinishReason = FinishReasonStop
	return response, nil
}

func newResponseMetadata(provider, model string, stage ExecutionStage) Response {
	return Response{
		Provider:     strings.TrimSpace(provider),
		Model:        strings.TrimSpace(model),
		Stage:        normalizedStage(stage),
		FinishReason: FinishReasonMissing,
	}
}

func addAttempt(response *Response, startedAt time.Time, err error) {
	if response == nil {
		return
	}
	response.Attempts = append(response.Attempts, Attempt{
		Provider:     response.Provider,
		Model:        response.Model,
		Stage:        normalizedStage(response.Stage),
		FinishReason: normalizedFinishReason(response.FinishReason),
		ErrorKind:    providerErrorKind(err),
		LatencyMS:    float64(time.Since(startedAt).Microseconds()) / 1000,
	})
}

func providerErrorKind(err error) ErrorKind {
	var providerErr *ProviderError
	if errors.As(err, &providerErr) {
		return providerErr.Kind
	}
	return ""
}

func normalizedStage(stage ExecutionStage) ExecutionStage {
	switch stage {
	case StagePrimary, StageFallback:
		return stage
	default:
		return StagePrimary
	}
}

func normalizedFinishReason(reason FinishReason) FinishReason {
	switch reason {
	case FinishReasonStop, FinishReasonLength, FinishReasonMissing, FinishReasonOther:
		return reason
	default:
		return FinishReasonMissing
	}
}
