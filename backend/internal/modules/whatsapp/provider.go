package whatsapp

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
)

var ErrMediaObjectNotFound = errors.New("whatsapp media object not found")

type ProviderRequest struct {
	DispatchType string
	StudentID    string
	Text         string
	ObjectKey    string
	FileName     string
	Metadata     map[string]any
}

type ProviderResult struct {
	ExternalMessageID string
}

type Provider interface {
	Send(ctx context.Context, req ProviderRequest) (ProviderResult, error)
}

type DeterministicProvider struct{}

func NewDeterministicProvider() *DeterministicProvider {
	return &DeterministicProvider{}
}

func (p *DeterministicProvider) Send(_ context.Context, req ProviderRequest) (ProviderResult, error) {
	if force, ok := req.Metadata["force_fail"].(bool); ok && force {
		return ProviderResult{}, errors.New("forced provider failure")
	}
	if strings.TrimSpace(req.Text) == "" && strings.TrimSpace(req.ObjectKey) == "" {
		return ProviderResult{}, errors.New("empty provider payload")
	}

	payload := req.DispatchType + "|" + req.StudentID + "|" + req.Text + "|" + req.ObjectKey
	sum := sha256.Sum256([]byte(payload))
	return ProviderResult{
		ExternalMessageID: "mock-" + hex.EncodeToString(sum[:8]),
	}, nil
}
