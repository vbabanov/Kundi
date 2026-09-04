package assistant

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/avatar_cues"
	"github.com/kundi/kundi/backend/internal/modules/assistant/context_builder"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/pedagogy_policy"
	"github.com/kundi/kundi/backend/internal/modules/assistant/persona_policy"
	"github.com/kundi/kundi/backend/internal/modules/assistant/ratelimit"
	"github.com/kundi/kundi/backend/internal/modules/assistant/response_renderer"
	"github.com/kundi/kundi/backend/internal/modules/assistant/safety"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tts"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tutoring"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

const DefaultLLMTimeout = 12 * time.Second

type Options struct {
	Enabled           *bool
	VoiceInputEnabled *bool
	SessionRepository SessionRepository
	AcademicContext   AcademicContextProvider
	InputLimits       safety.Limits
	Moderator         safety.Moderator
	RateLimiter       ratelimit.Limiter
	AudioURLValidator *safety.AudioURLValidator
	LLMTimeout        time.Duration
	Logger            *slog.Logger
}

type Service struct {
	personaLegacy *persona.Service
	context       *context_builder.Service
	personaPolicy *persona_policy.Service
	pedagogy      *pedagogy_policy.Service
	validator     *safety.InputValidator
	moderator     safety.Moderator
	output        *safety.OutputValidator
	safeResponses *safety.SafeResponseFactory
	renderer      *response_renderer.Service
	llm           llm.Provider
	tts           tts.Provider
	avatarCues    *avatar_cues.Service
	rateLimiter   ratelimit.Limiter
	audioURLs     *safety.AudioURLValidator
	llmTimeout    time.Duration
	logger        *slog.Logger
	enabled       bool
	voiceEnabled  bool
	sessions      SessionRepository
	academic      AcademicContextProvider
	tutoring      *tutoring.Service
}

func NewService(personaService *persona.Service, llmProvider llm.Provider, ttsProvider tts.Provider) *Service {
	return NewServiceWithOptions(personaService, llmProvider, ttsProvider, Options{})
}

func NewServiceWithOptions(personaService *persona.Service, llmProvider llm.Provider, ttsProvider tts.Provider, options Options) *Service {
	enabled := true
	if options.Enabled != nil {
		enabled = *options.Enabled
	}
	voiceEnabled := false
	if options.VoiceInputEnabled != nil {
		voiceEnabled = *options.VoiceInputEnabled
	}
	if personaService == nil {
		personaService = persona.NewService()
	}
	if llmProvider == nil {
		llmProvider = llm.NewDeterministicProvider()
	}
	if ttsProvider == nil {
		ttsProvider = tts.NewService("")
	}
	if options.Moderator == nil {
		options.Moderator = safety.NewPolicy()
	}
	if options.RateLimiter == nil {
		options.RateLimiter = ratelimit.NewInMemory(ratelimit.DefaultConfig())
	}
	if options.AudioURLValidator == nil {
		options.AudioURLValidator = safety.NewAudioURLValidator([]string{"cdn.kundi.local"})
	}
	if options.LLMTimeout <= 0 {
		options.LLMTimeout = DefaultLLMTimeout
	}
	if options.Logger == nil {
		options.Logger = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	return &Service{
		personaLegacy: personaService,
		context:       context_builder.NewService(),
		personaPolicy: persona_policy.NewService(),
		pedagogy:      pedagogy_policy.NewService(),
		validator:     safety.NewInputValidator(options.InputLimits),
		moderator:     options.Moderator,
		output:        safety.NewOutputValidator(options.Moderator),
		safeResponses: safety.NewSafeResponseFactory(),
		renderer:      response_renderer.NewService(),
		llm:           llmProvider,
		tts:           ttsProvider,
		avatarCues:    avatar_cues.NewService(),
		rateLimiter:   options.RateLimiter,
		audioURLs:     options.AudioURLValidator,
		llmTimeout:    options.LLMTimeout,
		logger:        options.Logger,
		enabled:       enabled,
		voiceEnabled:  voiceEnabled,
		sessions:      options.SessionRepository,
		academic:      options.AcademicContext,
		tutoring:      tutoring.NewService(),
	}
}

func (s *Service) Enabled() bool { return s != nil && s.enabled }

func (s *Service) Message(ctx context.Context, cmd MessageCommand) (Response, error) {
	startedAt := time.Now()
	studentID, err := uuid.Parse(strings.TrimSpace(cmd.StudentID))
	if err != nil {
		return Response{}, apperrors.BadRequest("assistant_student_id_invalid", "student id is invalid")
	}

	validationInput := safety.Input{
		Mode:       string(cmd.Mode),
		GradeLevel: cmd.GradeLevel,
		Text:       cmd.Text,
		History:    make([]safety.HistoryMessage, 0, len(cmd.History)),
	}
	for _, record := range cmd.History {
		validationInput.History = append(validationInput.History, safety.HistoryMessage{Role: record.Role, Text: record.Text})
	}
	validated, err := s.validator.Validate(validationInput)
	if err != nil {
		code := "assistant_input_invalid"
		message := "assistant input is invalid"
		var validationErr *safety.ValidationError
		if errors.As(err, &validationErr) {
			code = validationErr.Code
			message = validationErr.Message
		}
		s.logEvent(startedAt, studentID.String(), validationInput.Mode, validationInput.GradeLevel, "", validationInput.Text, validationInput.History, safety.CategoryNone, "not_called", code)
		return Response{}, apperrors.BadRequest(code, message)
	}

	modeRaw := validated.Mode
	gradeLevel := validated.GradeLevel
	language := safety.DetectLanguage(validated.Text)
	personaResolved, legacyPersona := s.resolvePersona(ctx, studentID, modeRaw, gradeLevel)
	if strings.TrimSpace(legacyPersona.ToneProfile) != "" {
		personaResolved.Tone = strings.TrimSpace(legacyPersona.ToneProfile)
	}
	if strings.TrimSpace(legacyPersona.StyleProfile) != "" {
		personaResolved.Style = strings.TrimSpace(legacyPersona.StyleProfile)
	}

	if cmd.EnforceRateLimit {
		limitDecision := s.rateLimiter.Allow(studentID.String())
		if !limitDecision.Allowed {
			response := s.safeResponses.ForRateLimit(language)
			s.logEvent(startedAt, studentID.String(), modeRaw, gradeLevel, personaResolved.GradeBand, validated.Text, validated.History, safety.CategoryNone, "not_called", "assistant_rate_limited")
			return Response{}, apperrors.New(http.StatusTooManyRequests, "assistant_rate_limited", response.Text, nil)
		}
	}

	inputModeration, err := s.moderator.Moderate(ctx, validated.Text)
	if err != nil {
		response := s.safeResponses.ForModerationFailure(language)
		s.logEvent(startedAt, studentID.String(), modeRaw, gradeLevel, personaResolved.GradeBand, validated.Text, validated.History, safety.CategoryUnknownRisk, "not_called", "assistant_input_moderation_failed")
		return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
	}
	if !inputModeration.Allowed {
		response := s.safeResponses.ForModeration(inputModeration)
		s.logEvent(startedAt, studentID.String(), modeRaw, gradeLevel, personaResolved.GradeBand, validated.Text, validated.History, inputModeration.Category, "not_called", inputModeration.ReasonCode)
		return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
	}
	for _, record := range validated.History {
		historyModeration, historyErr := s.moderator.Moderate(ctx, record.Text)
		if historyErr != nil {
			response := s.safeResponses.ForModerationFailure(language)
			s.logEvent(startedAt, studentID.String(), modeRaw, gradeLevel, personaResolved.GradeBand, validated.Text, validated.History, safety.CategoryUnknownRisk, "not_called", "assistant_history_moderation_failed")
			return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
		}
		if !historyModeration.Allowed {
			response := s.safeResponses.ForModeration(historyModeration)
			s.logEvent(startedAt, studentID.String(), modeRaw, gradeLevel, personaResolved.GradeBand, validated.Text, validated.History, historyModeration.Category, "not_called", historyModeration.ReasonCode)
			return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
		}
	}

	history := make([]context_builder.ChatRecord, 0, len(validated.History))
	for _, record := range validated.History {
		history = append(history, context_builder.ChatRecord{Role: record.Role, Text: record.Text})
	}
	builtContext := s.context.Build(context_builder.Input{Text: inputModeration.SanitizedText, History: history})

	pedagogy := s.pedagogy.Resolve(modeRaw, inputModeration.SanitizedText)
	renderedText := s.renderer.Render(modeRaw, personaResolved, builtContext)

	llmCtx, cancel := context.WithTimeout(ctx, s.llmTimeout)
	llmResponse, llmErr := s.llm.Generate(llmCtx, llm.Request{
		Mode:        modeRaw,
		Prompt:      renderedText,
		PersonaTone: personaResolved.Tone,
		Style:       personaResolved.Style,
		History:     builtContext.RecentUserMessages,
	})
	cancel()

	providerResult := "ok"
	errorCode := ""
	text := strings.TrimSpace(llmResponse.Text)
	if llmErr != nil || text == "" {
		providerResult, errorCode = classifyLLMFailure(llmErr, text)
		text = s.safeResponses.ForProviderFailure(language).Text
		pedagogy.SafetyIntervention = true
	}

	outputModeration, moderationErr := s.output.Validate(ctx, text)
	if moderationErr != nil {
		response := s.safeResponses.ForModerationFailure(language)
		s.logEvent(startedAt, studentID.String(), modeRaw, gradeLevel, personaResolved.GradeBand, validated.Text, validated.History, safety.CategoryUnknownRisk, providerResult, "assistant_output_moderation_failed")
		return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
	}
	if !outputModeration.Allowed {
		response := s.safeResponses.ForModeration(outputModeration)
		s.logEvent(startedAt, studentID.String(), modeRaw, gradeLevel, personaResolved.GradeBand, validated.Text, validated.History, outputModeration.Category, providerResult, "assistant_output_blocked")
		return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
	}
	text = outputModeration.SanitizedText

	audioURL, ttsErr := s.tts.Render(ctx, text)
	audioStatus := AudioStatusUnavailable
	cues := avatar_cues.Cue{Emotion: "neutral"}
	if ttsErr != nil {
		if errorCode == "" {
			errorCode = "assistant_tts_failed"
		}
	} else if strings.TrimSpace(audioURL) != "" {
		validatedAudioURL, audioErr := s.audioURLs.Validate(audioURL)
		if audioErr != nil {
			if errorCode == "" {
				errorCode = "assistant_audio_url_invalid"
			}
		} else {
			audioURL = validatedAudioURL
			audioStatus = AudioStatusReady
			cues = s.avatarCues.Build(text, personaResolved)
		}
	}
	if audioStatus != AudioStatusReady {
		audioURL = ""
	}

	gestureTags := make([]string, 0, 1)
	if cues.Gesture != "" {
		gestureTags = append(gestureTags, cues.Gesture)
	}
	response := Response{
		Text:          text,
		AudioURL:      audioURL,
		AudioStatus:   audioStatus,
		Visemes:       toContractVisemes(cues.Visemes),
		AvatarEmotion: cues.Emotion,
		GestureTags:   gestureTags,
		Pedagogy: PedagogyFlags{
			NeedsScaffold:      pedagogy.NeedsScaffold,
			ContainsHint:       pedagogy.ContainsHint,
			ContainsStepPlan:   pedagogy.ContainsStepPlan,
			SafetyIntervention: pedagogy.SafetyIntervention,
		},
		Behavior: behaviorMeta(modeRaw, gradeLevel, personaResolved),
	}
	s.logEvent(startedAt, studentID.String(), modeRaw, gradeLevel, personaResolved.GradeBand, validated.Text, validated.History, safety.CategoryNone, providerResult, errorCode)
	return response, nil
}

func (s *Service) resolvePersona(ctx context.Context, studentID uuid.UUID, mode string, gradeLevel int) (persona_policy.Persona, persona.Profile) {
	legacy := s.personaLegacy.Resolve(ctx, studentID, gradeLevel)
	return s.personaPolicy.Resolve(mode, gradeLevel), legacy
}

func (s *Service) safetyResponse(text, mode string, gradeLevel int, resolved persona_policy.Persona) Response {
	return Response{
		Text:          text,
		AudioURL:      "",
		AudioStatus:   AudioStatusUnavailable,
		Visemes:       nil,
		AvatarEmotion: "neutral",
		GestureTags:   nil,
		Pedagogy: PedagogyFlags{
			SafetyIntervention: true,
		},
		Behavior: behaviorMeta(mode, gradeLevel, resolved),
	}
}

func behaviorMeta(mode string, gradeLevel int, resolved persona_policy.Persona) BehaviorMeta {
	return BehaviorMeta{
		Mode:         mode,
		GradeLevel:   gradeLevel,
		GradeBand:    resolved.GradeBand,
		PersonaTone:  resolved.Tone,
		PersonaStyle: resolved.Style,
	}
}

func classifyLLMFailure(err error, text string) (string, string) {
	if err == nil && strings.TrimSpace(text) == "" {
		return "malformed_response", "assistant_llm_malformed_response"
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return "timeout", "assistant_llm_timeout"
	}
	if errors.Is(err, context.Canceled) {
		return "canceled", "assistant_llm_canceled"
	}
	var providerErr *llm.ProviderError
	if errors.As(err, &providerErr) {
		switch providerErr.Kind {
		case llm.ErrorClient:
			return "provider_4xx", "assistant_llm_provider_4xx"
		case llm.ErrorRateLimit:
			return "provider_429", "assistant_llm_provider_rate_limited"
		case llm.ErrorServer:
			return "provider_5xx", "assistant_llm_provider_5xx"
		case llm.ErrorUnavailable:
			return "provider_unavailable", "assistant_llm_provider_unavailable"
		case llm.ErrorTimeout:
			return "timeout", "assistant_llm_timeout"
		case llm.ErrorMalformed:
			return "malformed_response", "assistant_llm_malformed_response"
		case llm.ErrorConfiguration:
			return "misconfigured", "assistant_llm_misconfigured"
		}
	}
	return "internal_error", "assistant_llm_internal_error"
}

func (s *Service) logEvent(startedAt time.Time, studentID, mode string, gradeLevel int, gradeBand, text string, history []safety.HistoryMessage, category safety.SafetyCategory, providerResult, errorCode string) {
	historyRunes := 0
	for _, record := range history {
		historyRunes += utf8.RuneCountInString(record.Text)
	}
	s.logger.Info("assistant_request",
		slog.String("student_id", studentID),
		slog.String("mode", strings.TrimSpace(mode)),
		slog.Int("grade_level", gradeLevel),
		slog.String("grade_band", gradeBand),
		slog.Int("text_length", utf8.RuneCountInString(text)),
		slog.Int("history_messages", len(history)),
		slog.Int("history_length", historyRunes),
		slog.String("safety_category", string(category)),
		slog.String("provider_result", providerResult),
		slog.String("error_code", errorCode),
		slog.Int64("latency_ms", time.Since(startedAt).Milliseconds()),
	)
}

func toContractVisemes(items []avatar_cues.Viseme) []Viseme {
	out := make([]Viseme, 0, len(items))
	for _, item := range items {
		out = append(out, Viseme{OffsetMs: item.OffsetMs, ID: item.ID, Weight: item.Weight})
	}
	return out
}
