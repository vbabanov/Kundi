package llm

import (
	"context"
	"errors"
	"strings"
)

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
