package providerstatus

import (
	"strings"
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

func TestTTSStatusKeepsLegacyBehaviorWhenAzureTTSIsDisabled(t *testing.T) {
	cfg := config.Config{AI: config.AIConfig{TTSProvider: "deterministic"}}
	if got := ttsStatus(cfg); got != (Provider{Name: "tts", Mode: "deterministic", State: StateMock}) {
		t.Fatalf("unexpected legacy TTS status: %#v", got)
	}
}

func TestAzureSpeechTTSReadiness(t *testing.T) {
	const secret = "primary-key-must-never-appear-in-readiness"
	valid := config.AIConfig{
		KundiTTSEnabled:       true,
		AssistantEnabled:      true,
		VoiceInputEnabled:     true,
		AzureSpeechKeyPrimary: secret,
		AzureSpeechRegion:     "westus",
		AzureSpeechVoiceRU:    "ru-RU-SvetlanaNeural",
		AzureSpeechVoiceKK:    "kk-KZ-AigulNeural",
	}
	tests := []struct {
		name   string
		mutate func(*config.AIConfig)
		state  State
	}{
		{name: "complete configuration", state: StateReady},
		{name: "assistant disabled", mutate: func(c *config.AIConfig) { c.AssistantEnabled = false }, state: StateMisconfigured},
		{name: "voice input disabled", mutate: func(c *config.AIConfig) { c.VoiceInputEnabled = false }, state: StateMisconfigured},
		{name: "primary key missing", mutate: func(c *config.AIConfig) { c.AzureSpeechKeyPrimary = "" }, state: StateMisconfigured},
		{name: "region missing", mutate: func(c *config.AIConfig) { c.AzureSpeechRegion = "" }, state: StateMisconfigured},
		{name: "region invalid", mutate: func(c *config.AIConfig) { c.AzureSpeechRegion = "west-us" }, state: StateMisconfigured},
		{name: "wrong Russian voice", mutate: func(c *config.AIConfig) { c.AzureSpeechVoiceRU = "ru-RU-OtherNeural" }, state: StateMisconfigured},
		{name: "wrong Kazakh voice", mutate: func(c *config.AIConfig) { c.AzureSpeechVoiceKK = "kk-KZ-OtherNeural" }, state: StateMisconfigured},
		{name: "blank endpoint", state: StateReady},
		{name: "Azure resource endpoint", mutate: func(c *config.AIConfig) { c.AzureSpeechEndpoint = "https://kundi-speech.cognitiveservices.azure.com/" }, state: StateReady},
		{name: "HTTP endpoint", mutate: func(c *config.AIConfig) { c.AzureSpeechEndpoint = "http://westus.api.cognitive.microsoft.com" }, state: StateMisconfigured},
		{name: "non Azure endpoint", mutate: func(c *config.AIConfig) { c.AzureSpeechEndpoint = "https://speech.example.com" }, state: StateMisconfigured},
		{name: "userinfo endpoint", mutate: func(c *config.AIConfig) { c.AzureSpeechEndpoint = "https://user@westus.api.cognitive.microsoft.com" }, state: StateMisconfigured},
		{name: "query endpoint", mutate: func(c *config.AIConfig) {
			c.AzureSpeechEndpoint = "https://westus.api.cognitive.microsoft.com/?key=secret"
		}, state: StateMisconfigured},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			ai := valid
			if test.mutate != nil {
				test.mutate(&ai)
			}
			got := ttsStatus(config.Config{AI: ai})
			if got.Name != "tts" || got.Mode != "azure-speech" || got.State != test.state {
				t.Fatalf("unexpected Azure TTS readiness: %#v", got)
			}
			if strings.Contains(got.Reason, secret) {
				t.Fatalf("readiness reason leaked a configured value: %q", got.Reason)
			}
			if ai.AzureSpeechEndpoint != "" && strings.Contains(got.Reason, ai.AzureSpeechEndpoint) {
				t.Fatalf("readiness reason leaked a configured value: %q", got.Reason)
			}
		})
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
