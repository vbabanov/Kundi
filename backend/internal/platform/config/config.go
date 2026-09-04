package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	App           AppConfig
	Database      DatabaseConfig
	Storage       StorageConfig
	Security      SecurityConfig
	AI            AIConfig
	WhatsApp      WhatsAppConfig
	Jobs          JobsConfig
	Observability ObservabilityConfig
}

type AppConfig struct {
	Name         string
	Env          string
	Port         string
	LogLevel     string
	ReadTimeout  time.Duration
	WriteTimeout time.Duration
}

type DatabaseConfig struct {
	URL string
}

type StorageConfig struct {
	Provider      string
	Endpoint      string
	Bucket        string
	AccessKey     string
	SecretKey     string
	PublicBaseURL string
}

type SecurityConfig struct {
	AccessTokenSecret  string
	AccessTokenTTL     time.Duration
	RefreshTokenTTL    time.Duration
	FieldEncryptionKey string
}

type AIConfig struct {
	AssistantEnabled                  bool
	AlemBaseURL                       string
	AlemAPIKey                        string
	AlemPrimaryAPIKey                 string
	AlemFallbackAPIKey                string
	AlemPrimaryModel                  string
	AlemFallbackModel                 string
	WorkerConcurrency                 int
	LLMProvider                       string
	LLMBaseURL                        string
	LLMAPIKey                         string
	TTSProvider                       string
	TTSBaseURL                        string
	TTSAPIKey                         string
	TTSTrustedHosts                   []string
	AssistantLLMTimeout               time.Duration
	AssistantPrimaryTimeout           time.Duration
	AssistantFallbackTimeout          time.Duration
	AssistantMaxTextRunes             int
	AssistantMaxHistoryMessages       int
	AssistantMaxHistoryMessageRunes   int
	AssistantMaxHistoryRunes          int
	AssistantRateLimit                int
	AssistantRateWindow               time.Duration
	AssistantRateLimiterMaxIdentities int
}

type WhatsAppConfig struct {
	WorkerConcurrency int
	Provider          string
	BaseURL           string
	APIToken          string
}

type JobsConfig struct {
	LeaseDuration time.Duration
	PollInterval  time.Duration
	AutoMigrate   bool
}

type ObservabilityConfig struct {
	Mode string
}

func Load() (Config, error) {
	cfg := Config{
		App: AppConfig{
			Name:         env("APP_NAME", "kundi-backend"),
			Env:          env("APP_ENV", "dev"),
			Port:         env("APP_PORT", "8080"),
			LogLevel:     env("LOG_LEVEL", "info"),
			ReadTimeout:  time.Duration(envInt("HTTP_READ_TIMEOUT_SEC", 15)) * time.Second,
			WriteTimeout: time.Duration(envInt("HTTP_WRITE_TIMEOUT_SEC", 30)) * time.Second,
		},
		Database: DatabaseConfig{
			URL: env("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/kundi?sslmode=disable"),
		},
		Storage: StorageConfig{
			Provider:      env("OBJECT_STORAGE_PROVIDER", "s3"),
			Endpoint:      env("OBJECT_STORAGE_ENDPOINT", ""),
			Bucket:        env("OBJECT_STORAGE_BUCKET", "kundi-staging"),
			AccessKey:     env("OBJECT_STORAGE_ACCESS_KEY", ""),
			SecretKey:     env("OBJECT_STORAGE_SECRET_KEY", ""),
			PublicBaseURL: env("OBJECT_STORAGE_PUBLIC_BASE_URL", ""),
		},
		Security: SecurityConfig{
			AccessTokenSecret:  env("ACCESS_TOKEN_SECRET", ""),
			AccessTokenTTL:     time.Duration(envInt("ACCESS_TOKEN_TTL_MIN", 20)) * time.Minute,
			RefreshTokenTTL:    time.Duration(envInt("REFRESH_TOKEN_TTL_HOURS", 24*30)) * time.Hour,
			FieldEncryptionKey: env("FIELD_ENCRYPTION_KEY", ""),
		},
		AI: AIConfig{
			AssistantEnabled:                  envBool("KUNDI_ASSISTANT_ENABLED", false),
			AlemBaseURL:                       env("ALEM_BASE_URL", "https://llm.alem.ai/v1"),
			AlemAPIKey:                        env("ALEM_API_KEY", ""),
			AlemPrimaryAPIKey:                 env("ALEM_PRIMARY_API_KEY", ""),
			AlemFallbackAPIKey:                env("ALEM_FALLBACK_API_KEY", ""),
			AlemPrimaryModel:                  env("ALEM_PRIMARY_MODEL", ""),
			AlemFallbackModel:                 env("ALEM_FALLBACK_MODEL", ""),
			WorkerConcurrency:                 envInt("AI_WORKER_CONCURRENCY", 4),
			LLMProvider:                       env("AI_LLM_PROVIDER", "deterministic"),
			LLMBaseURL:                        env("AI_LLM_BASE_URL", ""),
			LLMAPIKey:                         env("AI_LLM_API_KEY", ""),
			TTSProvider:                       env("AI_TTS_PROVIDER", "deterministic"),
			TTSBaseURL:                        env("AI_TTS_BASE_URL", "https://cdn.kundi.local"),
			TTSAPIKey:                         env("AI_TTS_API_KEY", ""),
			TTSTrustedHosts:                   envList("AI_TTS_TRUSTED_HOSTS"),
			AssistantLLMTimeout:               time.Duration(envInt("AI_ASSISTANT_LLM_TIMEOUT_SEC", 12)) * time.Second,
			AssistantPrimaryTimeout:           time.Duration(envInt("AI_ASSISTANT_PRIMARY_TIMEOUT_SEC", 10)) * time.Second,
			AssistantFallbackTimeout:          time.Duration(envInt("AI_ASSISTANT_FALLBACK_TIMEOUT_SEC", 8)) * time.Second,
			AssistantMaxTextRunes:             envInt("AI_ASSISTANT_MAX_TEXT_RUNES", 4_000),
			AssistantMaxHistoryMessages:       envInt("AI_ASSISTANT_MAX_HISTORY_MESSAGES", 20),
			AssistantMaxHistoryMessageRunes:   envInt("AI_ASSISTANT_MAX_HISTORY_MESSAGE_RUNES", 4_000),
			AssistantMaxHistoryRunes:          envInt("AI_ASSISTANT_MAX_HISTORY_RUNES", 12_000),
			AssistantRateLimit:                envInt("AI_ASSISTANT_RATE_LIMIT", 20),
			AssistantRateWindow:               time.Duration(envInt("AI_ASSISTANT_RATE_WINDOW_SEC", 60)) * time.Second,
			AssistantRateLimiterMaxIdentities: envInt("AI_ASSISTANT_RATE_MAX_IDENTITIES", 10_000),
		},
		WhatsApp: WhatsAppConfig{
			WorkerConcurrency: envInt("WHATSAPP_WORKER_CONCURRENCY", 2),
			Provider:          env("WHATSAPP_PROVIDER", "deterministic"),
			BaseURL:           env("WHATSAPP_BASE_URL", ""),
			APIToken:          env("WHATSAPP_API_TOKEN", ""),
		},
		Jobs: JobsConfig{
			LeaseDuration: time.Duration(envInt("JOBS_LEASE_SEC", 45)) * time.Second,
			PollInterval:  time.Duration(envInt("JOBS_POLL_MS", 800)) * time.Millisecond,
			AutoMigrate:   envBool("DB_AUTO_MIGRATE", true),
		},
		Observability: ObservabilityConfig{
			Mode: env("OBSERVABILITY_MODE", "log"),
		},
	}

	if strings.TrimSpace(cfg.Security.AccessTokenSecret) == "" {
		return Config{}, fmt.Errorf("ACCESS_TOKEN_SECRET is required")
	}
	if strings.TrimSpace(cfg.Security.FieldEncryptionKey) == "" {
		return Config{}, fmt.Errorf("FIELD_ENCRYPTION_KEY is required")
	}
	if len(cfg.Security.FieldEncryptionKey) != 32 {
		return Config{}, fmt.Errorf("FIELD_ENCRYPTION_KEY must be exactly 32 bytes")
	}

	return cfg, nil
}

func env(key, fallback string) string {
	if v := os.Getenv(key); strings.TrimSpace(v) != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) int {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback
	}
	v, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return v
}

func envBool(key string, fallback bool) bool {
	raw := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	if raw == "" {
		return fallback
	}
	switch raw {
	case "1", "true", "yes", "y", "on":
		return true
	case "0", "false", "no", "n", "off":
		return false
	default:
		return fallback
	}
}

func envList(key string) []string {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return nil
	}
	items := make([]string, 0)
	for _, item := range strings.Split(raw, ",") {
		if trimmed := strings.TrimSpace(item); trimmed != "" {
			items = append(items, trimmed)
		}
	}
	return items
}
