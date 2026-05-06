package app

import (
	"context"
	"log/slog"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kundi/kundi/backend/internal/modules/academic"
	analyticsmodule "github.com/kundi/kundi/backend/internal/modules/analytics"
	assistantmodule "github.com/kundi/kundi/backend/internal/modules/assistant"
	assistantllm "github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	assistanttts "github.com/kundi/kundi/backend/internal/modules/assistant/tts"
	auditmodule "github.com/kundi/kundi/backend/internal/modules/audit"
	authmodule "github.com/kundi/kundi/backend/internal/modules/auth"
	ingestmodule "github.com/kundi/kundi/backend/internal/modules/diary_ingest"
	jobsmodule "github.com/kundi/kundi/backend/internal/modules/jobs"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	"github.com/kundi/kundi/backend/internal/modules/profiles"
	"github.com/kundi/kundi/backend/internal/modules/students"
	whatsappmodule "github.com/kundi/kundi/backend/internal/modules/whatsapp"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
	"github.com/kundi/kundi/backend/internal/platform/crypto"
	"github.com/kundi/kundi/backend/internal/platform/db"
	"github.com/kundi/kundi/backend/internal/platform/idempotency"
	"github.com/kundi/kundi/backend/internal/platform/logger"
	"github.com/kundi/kundi/backend/internal/platform/observability"
)

type Bootstrap struct {
	Config config.Config
	Logger *slog.Logger
	Pool   *pgxpool.Pool

	AccessTokens *platformauth.AccessTokenService
	Idempotency  *idempotency.Store
	Observe      observability.Hooks

	AuthService      *authmodule.Service
	ProfilesService  *profiles.Service
	IngestService    *ingestmodule.Service
	AcademicService  *academic.Service
	AnalyticsService *analyticsmodule.Service
	AssistantService *assistantmodule.Service
	JobsService      *jobsmodule.Service
	WhatsAppService  *whatsappmodule.Service
	WhatsAppDispatch *whatsappmodule.DispatchProcessor
	AuditService     *auditmodule.Service
}

func New(ctx context.Context, serviceName string) (*Bootstrap, error) {
	cfg, err := config.Load()
	if err != nil {
		return nil, err
	}
	log := logger.New(serviceName, cfg.App.LogLevel)
	pool, err := db.Connect(ctx, cfg.Database.URL)
	if err != nil {
		return nil, err
	}
	if cfg.Jobs.AutoMigrate {
		if err := db.RunMigrations(ctx, pool, "migrations"); err != nil {
			pool.Close()
			return nil, err
		}
	}
	cipher, err := crypto.NewFieldCipher(cfg.Security.FieldEncryptionKey)
	if err != nil {
		pool.Close()
		return nil, err
	}
	observe := observability.New(
		observability.Config{Mode: cfg.Observability.Mode},
		log,
	)

	accessTokens := platformauth.NewAccessTokenService(cfg.Security.AccessTokenSecret, cfg.Security.AccessTokenTTL)
	sessionStore := platformauth.NewRefreshSessionStore(pool)
	authRepo := authmodule.NewPostgresAccountRepository(pool)
	authService := authmodule.NewService(authRepo, cipher, accessTokens, sessionStore, cfg.Security.RefreshTokenTTL)

	studentRepo := students.NewRepository(pool)
	profilesService := profiles.NewService(studentRepo)
	ingestRepo := ingestmodule.NewPostgresRepository(pool)
	ingestService := ingestmodule.NewService(ingestRepo, observe)
	academicService := academic.NewService(pool, observe)
	analyticsService := analyticsmodule.NewService(pool)
	personaService := persona.NewService()
	assistantService := assistantmodule.NewService(
		personaService,
		resolveLLMProvider(cfg.AI.LLMProvider, cfg.AI.LLMBaseURL, cfg.AI.LLMAPIKey),
		resolveTTSProvider(cfg.AI.TTSProvider, cfg.AI.TTSBaseURL, cfg.AI.TTSAPIKey),
	)

	jobsRepo := jobsmodule.NewPostgresRepository(pool)
	jobsService := jobsmodule.NewService(jobsRepo)
	whatsAppService := whatsappmodule.NewService(jobsService)
	whatsAppDispatch := whatsappmodule.NewDispatchProcessor(
		whatsappmodule.NewPostgresDispatchStore(pool),
		resolveWhatsAppProvider(cfg.WhatsApp.Provider, cfg.WhatsApp.BaseURL, cfg.WhatsApp.APIToken),
	)
	auditService := auditmodule.NewService(pool)

	return &Bootstrap{
		Config:           cfg,
		Logger:           log,
		Pool:             pool,
		AccessTokens:     accessTokens,
		Idempotency:      idempotency.NewStore(pool),
		Observe:          observe,
		AuthService:      authService,
		ProfilesService:  profilesService,
		IngestService:    ingestService,
		AcademicService:  academicService,
		AnalyticsService: analyticsService,
		AssistantService: assistantService,
		JobsService:      jobsService,
		WhatsAppService:  whatsAppService,
		WhatsAppDispatch: whatsAppDispatch,
		AuditService:     auditService,
	}, nil
}

func (b *Bootstrap) Close() {
	if b != nil && b.Pool != nil {
		b.Pool.Close()
	}
}

func resolveLLMProvider(providerName string, baseURL string, apiKey string) assistantllm.Provider {
	switch strings.TrimSpace(strings.ToLower(providerName)) {
	case "http":
		if strings.TrimSpace(baseURL) == "" || strings.TrimSpace(apiKey) == "" {
			return assistantllm.NewDeterministicProvider()
		}
		return assistantllm.NewHTTPProvider(baseURL, apiKey)
	case "", "deterministic", "mock":
		return assistantllm.NewDeterministicProvider()
	default:
		return assistantllm.NewDeterministicProvider()
	}
}

func resolveTTSProvider(providerName string, baseURL string, apiKey string) assistanttts.Provider {
	switch strings.TrimSpace(strings.ToLower(providerName)) {
	case "http":
		if strings.TrimSpace(baseURL) == "" || strings.TrimSpace(apiKey) == "" {
			return assistanttts.NewService(baseURL)
		}
		return assistanttts.NewHTTPProvider(baseURL, apiKey)
	case "", "deterministic", "mock":
		return assistanttts.NewService(baseURL)
	default:
		return assistanttts.NewService(baseURL)
	}
}

func resolveWhatsAppProvider(providerName string, baseURL string, apiKey string) whatsappmodule.Provider {
	switch strings.TrimSpace(strings.ToLower(providerName)) {
	case "http":
		if strings.TrimSpace(baseURL) == "" || strings.TrimSpace(apiKey) == "" {
			return whatsappmodule.NewDeterministicProvider()
		}
		return whatsappmodule.NewHTTPProvider(baseURL, apiKey)
	case "", "deterministic", "mock":
		return whatsappmodule.NewDeterministicProvider()
	default:
		return whatsappmodule.NewDeterministicProvider()
	}
}
