package llm

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

type ErrorKind string

const (
	ErrorClient        ErrorKind = "provider_client_error"
	ErrorServer        ErrorKind = "provider_server_error"
	ErrorMalformed     ErrorKind = "provider_malformed_response"
	ErrorConfiguration ErrorKind = "provider_configuration_error"
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
	Text string
}

type Provider interface {
	Generate(ctx context.Context, req Request) (Response, error)
}

type DeterministicProvider struct{}

func NewDeterministicProvider() *DeterministicProvider {
	return &DeterministicProvider{}
}

func (p *DeterministicProvider) Generate(_ context.Context, req Request) (Response, error) {
	prompt := strings.TrimSpace(req.Prompt)
	if prompt == "" {
		return Response{}, errors.New("empty prompt")
	}
	if strings.Contains(strings.ToLower(prompt), "[llm:fail]") {
		return Response{}, errors.New("forced llm failure")
	}
	return Response{
		Text: "[" + req.Mode + "|" + req.PersonaTone + "|" + req.Style + "] " + prompt,
	}, nil
}
