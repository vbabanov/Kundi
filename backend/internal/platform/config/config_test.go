package config

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestAssistantDefaultsDisabledWithoutModelGuessing(t *testing.T) {
	t.Setenv("ACCESS_TOKEN_SECRET", "test-secret")
	t.Setenv("FIELD_ENCRYPTION_KEY", "12345678901234567890123456789012")
	t.Setenv("KUNDI_ASSISTANT_ENABLED", "")
	t.Setenv("KUNDI_ASSISTANT_ROLLOUT_MODE", "")
	t.Setenv("KUNDI_ASSISTANT_CANARY_STUDENT_IDS", "")
	t.Setenv("KUNDI_VOICE_INPUT_ENABLED", "")
	t.Setenv("KUNDI_TTS_ENABLED", "")
	t.Setenv("ALEM_BASE_URL", "")
	t.Setenv("ALEM_API_KEY", "")
	t.Setenv("ALEM_PRIMARY_API_KEY", "")
	t.Setenv("ALEM_FALLBACK_API_KEY", "")
	t.Setenv("ALEM_PRIMARY_MODEL", "")
	t.Setenv("ALEM_FALLBACK_MODEL", "")
	t.Setenv("AI_ASSISTANT_PRIMARY_TIMEOUT_SEC", "")
	t.Setenv("AI_ASSISTANT_FALLBACK_TIMEOUT_SEC", "")
	t.Setenv("AI_ASSISTANT_LLM_TIMEOUT_SEC", "")
	t.Setenv("AI_ASSISTANT_HOMEWORK_OVERDUE_DAYS", "")
	t.Setenv("AI_ASSISTANT_HOMEWORK_UPCOMING_DAYS", "")
	t.Setenv("AI_ASSISTANT_HOMEWORK_UNDATED_DAYS", "")
	t.Setenv("AI_ASSISTANT_ACADEMIC_RESULT_DAYS", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if cfg.AI.AssistantEnabled {
		t.Fatal("assistant must be disabled by default")
	}
	if cfg.AI.AssistantRolloutMode != AssistantRolloutModeAllowlist || len(cfg.AI.AssistantCanaryStudentIDs) != 0 {
		t.Fatalf("assistant rollout must default to an empty fail-closed allowlist: %#v", cfg.AI)
	}
	if cfg.AI.VoiceInputEnabled {
		t.Fatal("voice input must be disabled by default")
	}
	if cfg.AI.KundiTTSEnabled {
		t.Fatal("TTS must be disabled by default")
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
	if cfg.AI.AssistantHomeworkOverdueDays != 21 || cfg.AI.AssistantHomeworkUpcomingDays != 30 || cfg.AI.AssistantHomeworkUndatedDays != 21 || cfg.AI.AssistantAcademicResultDays != 120 {
		t.Fatalf("unexpected academic context windows: %#v", cfg.AI)
	}
}

func TestLoadDatabaseDoesNotRequireApplicationCredentials(t *testing.T) {
	t.Setenv("ACCESS_TOKEN_SECRET", "")
	t.Setenv("FIELD_ENCRYPTION_KEY", "")
	t.Setenv("DATABASE_URL", "postgres://migration-only.invalid/kundi")

	cfg := LoadDatabase()
	if cfg.URL != "postgres://migration-only.invalid/kundi" {
		t.Fatalf("database URL = %q", cfg.URL)
	}
}

func TestAssistantReadsNamedAlemSettings(t *testing.T) {
	t.Setenv("ACCESS_TOKEN_SECRET", "test-secret")
	t.Setenv("FIELD_ENCRYPTION_KEY", "12345678901234567890123456789012")
	t.Setenv("KUNDI_ASSISTANT_ENABLED", "true")
	t.Setenv("KUNDI_ASSISTANT_ROLLOUT_MODE", "all")
	t.Setenv("KUNDI_ASSISTANT_CANARY_STUDENT_IDS", "")
	t.Setenv("KUNDI_VOICE_INPUT_ENABLED", "true")
	t.Setenv("ALEM_BASE_URL", "https://example.invalid/v1")
	t.Setenv("ALEM_API_KEY", "legacy-secret-value")
	t.Setenv("ALEM_PRIMARY_API_KEY", "primary-secret-value")
	t.Setenv("ALEM_FALLBACK_API_KEY", "fallback-secret-value")
	t.Setenv("ALEM_PRIMARY_MODEL", "primary-exact-id")
	t.Setenv("ALEM_FALLBACK_MODEL", "fallback-exact-id")
	t.Setenv("AI_ASSISTANT_PRIMARY_TIMEOUT_SEC", "9")
	t.Setenv("AI_ASSISTANT_FALLBACK_TIMEOUT_SEC", "7")
	t.Setenv("AI_ASSISTANT_LLM_TIMEOUT_SEC", "11")
	t.Setenv("AI_ASSISTANT_HOMEWORK_OVERDUE_DAYS", "14")
	t.Setenv("AI_ASSISTANT_HOMEWORK_UPCOMING_DAYS", "20")
	t.Setenv("AI_ASSISTANT_HOMEWORK_UNDATED_DAYS", "10")
	t.Setenv("AI_ASSISTANT_ACADEMIC_RESULT_DAYS", "90")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if !cfg.AI.AssistantEnabled || !cfg.AI.VoiceInputEnabled || cfg.AI.AlemBaseURL != "https://example.invalid/v1" {
		t.Fatalf("unexpected assistant config: enabled=%t voice=%t base=%q", cfg.AI.AssistantEnabled, cfg.AI.VoiceInputEnabled, cfg.AI.AlemBaseURL)
	}
	if cfg.AI.AlemAPIKey != "legacy-secret-value" || cfg.AI.AlemPrimaryAPIKey != "primary-secret-value" || cfg.AI.AlemFallbackAPIKey != "fallback-secret-value" || cfg.AI.AlemPrimaryModel != "primary-exact-id" || cfg.AI.AlemFallbackModel != "fallback-exact-id" {
		t.Fatal("named Alem settings were not loaded")
	}
	if cfg.AI.AssistantPrimaryTimeout != 9*time.Second || cfg.AI.AssistantFallbackTimeout != 7*time.Second || cfg.AI.AssistantLLMTimeout != 11*time.Second {
		t.Fatal("named assistant timeout settings were not loaded")
	}
	if cfg.AI.AssistantHomeworkOverdueDays != 14 || cfg.AI.AssistantHomeworkUpcomingDays != 20 || cfg.AI.AssistantHomeworkUndatedDays != 10 || cfg.AI.AssistantAcademicResultDays != 90 {
		t.Fatal("named academic context windows were not loaded")
	}
}

func TestAssistantRolloutConfiguration(t *testing.T) {
	setRequiredConfig(t)
	first := uuid.New()
	second := uuid.New()
	tests := []struct {
		name      string
		enabled   string
		mode      string
		ids       string
		wantError bool
		wantMode  string
		wantIDs   int
	}{
		{name: "disabled without allowlist", enabled: "false", wantMode: AssistantRolloutModeAllowlist},
		{name: "enabled empty allowlist", enabled: "true", wantError: true},
		{name: "malformed UUID", enabled: "true", ids: "not-a-uuid", wantError: true},
		{name: "duplicates deduplicated", enabled: "true", ids: first.String() + ", " + first.String() + "," + second.String(), wantMode: AssistantRolloutModeAllowlist, wantIDs: 2},
		{name: "explicit all", enabled: "true", mode: "all", ids: "not-used", wantMode: AssistantRolloutModeAll},
		{name: "invalid mode", enabled: "false", mode: "percentage", wantError: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("KUNDI_ASSISTANT_ENABLED", test.enabled)
			t.Setenv("KUNDI_ASSISTANT_ROLLOUT_MODE", test.mode)
			t.Setenv("KUNDI_ASSISTANT_CANARY_STUDENT_IDS", test.ids)
			cfg, err := Load()
			if test.wantError {
				if err == nil {
					t.Fatal("expected fail-closed configuration error")
				}
				return
			}
			if err != nil {
				t.Fatalf("load: %v", err)
			}
			if cfg.AI.AssistantRolloutMode != test.wantMode || len(cfg.AI.AssistantCanaryStudentIDs) != test.wantIDs {
				t.Fatalf("unexpected rollout mode=%q ids=%d", cfg.AI.AssistantRolloutMode, len(cfg.AI.AssistantCanaryStudentIDs))
			}
		})
	}
}

func setRequiredConfig(t *testing.T) {
	t.Helper()
	t.Setenv("ACCESS_TOKEN_SECRET", "test-secret")
	t.Setenv("FIELD_ENCRYPTION_KEY", "12345678901234567890123456789012")
}
