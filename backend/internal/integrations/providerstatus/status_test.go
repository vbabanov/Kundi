package providerstatus

import (
	"testing"

	"github.com/kundi/kundi/backend/internal/platform/config"
)

func TestBuildDetectsMisconfiguredHTTPProviders(t *testing.T) {
	cfg := config.Config{
		AI: config.AIConfig{
			LLMProvider: "http",
			TTSProvider: "http",
			TTSBaseURL:  "https://tts.local",
		},
		WhatsApp: config.WhatsAppConfig{
			Provider: "http",
			BaseURL:  "https://wa.local",
		},
	}
	snapshot := Build(cfg)
	if snapshot.LLM.State != StateMisconfigured {
		t.Fatalf("expected llm misconfigured")
	}
	if snapshot.TTS.State != StateMisconfigured {
		t.Fatalf("expected tts misconfigured")
	}
	if snapshot.WhatsApp.State != StateMisconfigured {
		t.Fatalf("expected whatsapp misconfigured")
	}
	if !snapshot.HasMisconfiguredProvider() {
		t.Fatalf("expected misconfigured provider snapshot")
	}
}

func TestBuildDeterministicModesAreMock(t *testing.T) {
	cfg := config.Config{
		AI: config.AIConfig{
			LLMProvider: "deterministic",
			TTSProvider: "deterministic",
		},
		WhatsApp: config.WhatsAppConfig{
			Provider: "mock",
		},
	}
	snapshot := Build(cfg)
	if snapshot.LLM.State != StateMock || snapshot.TTS.State != StateMock || snapshot.WhatsApp.State != StateMock {
		t.Fatalf("expected mock states for deterministic providers")
	}
	if snapshot.HasMisconfiguredProvider() {
		t.Fatalf("expected no misconfigured providers")
	}
}

func TestBuildHTTPModesAreReadyWhenSecretsPresent(t *testing.T) {
	cfg := config.Config{
		AI: config.AIConfig{
			LLMProvider: "http",
			LLMBaseURL:  "https://llm.local",
			LLMAPIKey:   "llm-key",
			TTSProvider: "http",
			TTSBaseURL:  "https://tts.local",
			TTSAPIKey:   "tts-key",
		},
		WhatsApp: config.WhatsAppConfig{
			Provider: "http",
			BaseURL:  "https://wa.local",
			APIToken: "wa-key",
		},
	}
	snapshot := Build(cfg)
	if snapshot.LLM.State != StateReady {
		t.Fatalf("expected llm ready state")
	}
	if snapshot.TTS.State != StateReady {
		t.Fatalf("expected tts ready state")
	}
	if snapshot.WhatsApp.State != StateReady {
		t.Fatalf("expected whatsapp ready state")
	}
	if snapshot.HasMisconfiguredProvider() {
		t.Fatalf("expected no misconfigured providers")
	}
}

func TestBuildAlemSeparateKeysAreReady(t *testing.T) {
	cfg := config.Config{AI: config.AIConfig{
		AssistantEnabled:   true,
		AlemBaseURL:        "https://llm.example/v1",
		AlemPrimaryAPIKey:  "primary-test-key",
		AlemFallbackAPIKey: "fallback-test-key",
		AlemPrimaryModel:   "primary-model",
		AlemFallbackModel:  "fallback-model",
	}}
	if snapshot := Build(cfg); snapshot.LLM.State != StateReady {
		t.Fatalf("expected separate Alem credentials to be ready, got %#v", snapshot.LLM)
	}
}

func TestBuildAlemRequiresCredentialForConfiguredFallback(t *testing.T) {
	cfg := config.Config{AI: config.AIConfig{
		AssistantEnabled:  true,
		AlemBaseURL:       "https://llm.example/v1",
		AlemPrimaryAPIKey: "primary-test-key",
		AlemPrimaryModel:  "primary-model",
		AlemFallbackModel: "fallback-model",
	}}
	snapshot := Build(cfg)
	if snapshot.LLM.State != StateMisconfigured || snapshot.LLM.Reason == "" {
		t.Fatalf("expected missing fallback credential to be reported, got %#v", snapshot.LLM)
	}
}

func TestBuildAlemAcceptsSeparateKeys(t *testing.T) {
	cfg := config.Config{AI: config.AIConfig{
		AssistantEnabled:   true,
		AlemBaseURL:        "https://llm.example/v1",
		AlemPrimaryAPIKey:  "primary-key",
		AlemFallbackAPIKey: "fallback-key",
		AlemPrimaryModel:   "primary-model",
		AlemFallbackModel:  "fallback-model",
	}}
	if snapshot := Build(cfg); snapshot.LLM.State != StateReady {
		t.Fatalf("expected separate Alem keys to be ready, got %#v", snapshot.LLM)
	}
}

func TestBuildAlemAcceptsLegacySharedKey(t *testing.T) {
	cfg := config.Config{AI: config.AIConfig{
		AssistantEnabled:  true,
		AlemBaseURL:       "https://llm.example/v1",
		AlemAPIKey:        "shared-key",
		AlemPrimaryModel:  "primary-model",
		AlemFallbackModel: "fallback-model",
	}}
	if snapshot := Build(cfg); snapshot.LLM.State != StateReady {
		t.Fatalf("expected legacy shared Alem key to be ready, got %#v", snapshot.LLM)
	}
}
