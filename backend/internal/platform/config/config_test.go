package config

import (
	"testing"
	"time"
)

func TestAssistantDefaultsDisabledWithoutModelGuessing(t *testing.T) {
	t.Setenv("ACCESS_TOKEN_SECRET", "test-secret")
	t.Setenv("FIELD_ENCRYPTION_KEY", "12345678901234567890123456789012")
	t.Setenv("KUNDI_ASSISTANT_ENABLED", "")
	t.Setenv("ALEM_BASE_URL", "")
	t.Setenv("ALEM_API_KEY", "")
	t.Setenv("ALEM_PRIMARY_API_KEY", "")
	t.Setenv("ALEM_FALLBACK_API_KEY", "")
	t.Setenv("ALEM_PRIMARY_MODEL", "")
	t.Setenv("ALEM_FALLBACK_MODEL", "")
	t.Setenv("AI_ASSISTANT_PRIMARY_TIMEOUT_SEC", "")
	t.Setenv("AI_ASSISTANT_FALLBACK_TIMEOUT_SEC", "")
	t.Setenv("AI_ASSISTANT_LLM_TIMEOUT_SEC", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if cfg.AI.AssistantEnabled {
		t.Fatal("assistant must be disabled by default")
	}
	if cfg.AI.AlemBaseURL != "https://llm.alem.ai/v1" {
		t.Fatalf("unexpected Alem base URL: %q", cfg.AI.AlemBaseURL)
	}
	if cfg.AI.AlemAPIKey != "" || cfg.AI.AlemPrimaryAPIKey != "" || cfg.AI.AlemFallbackAPIKey != "" || cfg.AI.AlemPrimaryModel != "" || cfg.AI.AlemFallbackModel != "" {
		t.Fatal("Alem credentials and exact model IDs must not have guessed defaults")
	}
	if cfg.AI.AssistantPrimaryTimeout != 10*time.Second || cfg.AI.AssistantFallbackTimeout != 8*time.Second || cfg.AI.AssistantLLMTimeout != 12*time.Second {
		t.Fatalf("unexpected canary timeout policy: primary=%s fallback=%s total=%s", cfg.AI.AssistantPrimaryTimeout, cfg.AI.AssistantFallbackTimeout, cfg.AI.AssistantLLMTimeout)
	}
}

func TestAssistantReadsNamedAlemSettings(t *testing.T) {
	t.Setenv("ACCESS_TOKEN_SECRET", "test-secret")
	t.Setenv("FIELD_ENCRYPTION_KEY", "12345678901234567890123456789012")
	t.Setenv("KUNDI_ASSISTANT_ENABLED", "true")
	t.Setenv("ALEM_BASE_URL", "https://example.invalid/v1")
	t.Setenv("ALEM_API_KEY", "legacy-secret-value")
	t.Setenv("ALEM_PRIMARY_API_KEY", "primary-secret-value")
	t.Setenv("ALEM_FALLBACK_API_KEY", "fallback-secret-value")
	t.Setenv("ALEM_PRIMARY_MODEL", "primary-exact-id")
	t.Setenv("ALEM_FALLBACK_MODEL", "fallback-exact-id")
	t.Setenv("AI_ASSISTANT_PRIMARY_TIMEOUT_SEC", "9")
	t.Setenv("AI_ASSISTANT_FALLBACK_TIMEOUT_SEC", "7")
	t.Setenv("AI_ASSISTANT_LLM_TIMEOUT_SEC", "11")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if !cfg.AI.AssistantEnabled || cfg.AI.AlemBaseURL != "https://example.invalid/v1" {
		t.Fatalf("unexpected assistant config: enabled=%t base=%q", cfg.AI.AssistantEnabled, cfg.AI.AlemBaseURL)
	}
	if cfg.AI.AlemAPIKey != "legacy-secret-value" || cfg.AI.AlemPrimaryAPIKey != "primary-secret-value" || cfg.AI.AlemFallbackAPIKey != "fallback-secret-value" || cfg.AI.AlemPrimaryModel != "primary-exact-id" || cfg.AI.AlemFallbackModel != "fallback-exact-id" {
		t.Fatal("named Alem settings were not loaded")
	}
	if cfg.AI.AssistantPrimaryTimeout != 9*time.Second || cfg.AI.AssistantFallbackTimeout != 7*time.Second || cfg.AI.AssistantLLMTimeout != 11*time.Second {
		t.Fatal("named assistant timeout settings were not loaded")
	}
}
