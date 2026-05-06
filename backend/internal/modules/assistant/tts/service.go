package tts

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

type Provider interface {
	Render(ctx context.Context, text string) (string, error)
}

type Service struct {
	baseURL string
}

func NewService(baseURL string) *Service {
	return &Service{baseURL: strings.TrimRight(baseURL, "/")}
}

func (s *Service) Render(ctx context.Context, text string) (string, error) {
	_ = ctx
	return s.RenderURL(text), nil
}

func (s *Service) RenderURL(text string) string {
	if strings.TrimSpace(text) == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(text))
	if s.baseURL == "" {
		return "https://cdn.kundi.local/audio/" + hex.EncodeToString(sum[:]) + ".mp3"
	}
	return s.baseURL + "/audio/" + hex.EncodeToString(sum[:]) + ".mp3"
}
