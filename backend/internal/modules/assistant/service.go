package assistant

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/avatar_cues"
	"github.com/kundi/kundi/backend/internal/modules/assistant/context_builder"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/pedagogy_policy"
	"github.com/kundi/kundi/backend/internal/modules/assistant/persona_policy"
	"github.com/kundi/kundi/backend/internal/modules/assistant/ratelimit"
	"github.com/kundi/kundi/backend/internal/modules/assistant/response_renderer"
	"github.com/kundi/kundi/backend/internal/modules/assistant/safety"
	"github.com/kundi/kundi/backend/internal/modules/assistant/speechauth"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tts"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tutoring"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
	"github.com/kundi/kundi/backend/internal/platform/observability"
)

const DefaultLLMTimeout = 12 * time.Second

type Options struct {
	SpeechBroker      SpeechAuthorizer
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
	CanaryGate        *CanaryGate
	Observe           observability.Hooks
}

type Service struct {
	speechBroker  SpeechAuthorizer
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
	canaryGate    *CanaryGate
	observe       observability.Hooks
}

type SpeechAuthorizer interface {
	Enabled() bool
	AllowRequest(studentID string) bool
	Authorize(ctx context.Context, studentID, messageID, locale, hash string) (speechauth.Authorization, error)
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
		speechBroker:  options.SpeechBroker,
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
		canaryGate:    options.CanaryGate,
		observe:       observability.Ensure(options.Observe),
	}
}

func (s *Service) Enabled() bool { return s != nil && s.enabled }

func (s *Service) Message(ctx context.Context, cmd MessageCommand) (response Response, retErr error) {
	outcome := newAssistantOutcome(s.observe.Metrics, OperationLegacyMessage, "legacy")
	defer func() { outcome.Finish(retErr) }()
	if !s.Enabled() {
		return Response{}, apperrors.NotFound("assistant_disabled", "assistant is not enabled")
	}
	studentID, err := uuid.Parse(strings.TrimSpace(cmd.StudentID))
	if err != nil {
		return Response{}, apperrors.BadRequest("assistant_student_id_invalid", "student id is invalid")
	}
	if !s.canaryGate.Allows(studentID) {
		return Response{}, assistantUnavailable()
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
		outcome.SetResult(OutcomeValidation, OutcomeValidation)
		return Response{}, apperrors.BadRequest(code, message)
	}

	modeRaw := validated.Mode
	gradeLevel := validated.GradeLevel
	language := safety.DetectLanguage(validated.Text)
	outcome.SetLocale(string(language))
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
			outcome.SetResult(OutcomeRateLimited, OutcomeRateLimited)
			return Response{}, apperrors.New(http.StatusTooManyRequests, "assistant_rate_limited", response.Text, nil)
		}
	}

	inputModeration, err := s.moderator.Moderate(ctx, validated.Text)
	if err != nil {
		response := s.safeResponses.ForModerationFailure(language)
		outcome.SetSafety(safety.CategoryUnknownRisk)
		outcome.SetResult(OutcomeSafetyIntervention, OutcomeSafetyIntervention)
		return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
	}
	if !inputModeration.Allowed {
		response := s.safeResponses.ForModeration(inputModeration)
		outcome.SetSafety(inputModeration.Category)
		outcome.SetResult(OutcomeSafetyIntervention, OutcomeSafetyIntervention)
		return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
	}
	for _, record := range validated.History {
		historyModeration, historyErr := s.moderator.Moderate(ctx, record.Text)
		if historyErr != nil {
			response := s.safeResponses.ForModerationFailure(language)
			outcome.SetSafety(safety.CategoryUnknownRisk)
			outcome.SetResult(OutcomeSafetyIntervention, OutcomeSafetyIntervention)
			return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
		}
		if !historyModeration.Allowed {
			response := s.safeResponses.ForModeration(historyModeration)
			outcome.SetSafety(historyModeration.Category)
			outcome.SetResult(OutcomeSafetyIntervention, OutcomeSafetyIntervention)
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
	generation := newAssistantGenerationOutcome(s.observe.Metrics, string(language), "legacy")
	llmResponse, llmErr := s.llm.Generate(llmCtx, llm.Request{
		Mode:        modeRaw,
		Prompt:      renderedText,
		PersonaTone: personaResolved.Tone,
		Style:       personaResolved.Style,
		History:     builtContext.RecentUserMessages,
	})
	cancel()
	generation.Finish(llmResponse, llmErr)
	outcome.SetExecution(llmResponse)

	text := strings.TrimSpace(llmResponse.Text)
	providerFailed := llmErr != nil || text == ""
	if providerFailed {
		result, errorKind := assistantOutcomeFromProvider(llmErr, text != "")
		outcome.SetResult(result, errorKind)
		text = s.safeResponses.ForProviderFailure(language).Text
		pedagogy.SafetyIntervention = true
	}

	outputModeration, moderationErr := s.output.Validate(ctx, text)
	if moderationErr != nil {
		response := s.safeResponses.ForModerationFailure(language)
		outcome.SetSafety(safety.CategoryUnknownRisk)
		outcome.SetResult(OutcomeSafetyIntervention, OutcomeSafetyIntervention)
		return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
	}
	if !outputModeration.Allowed {
		response := s.safeResponses.ForModeration(outputModeration)
		outcome.SetSafety(outputModeration.Category)
		outcome.SetResult(OutcomeSafetyIntervention, OutcomeSafetyIntervention)
		return s.safetyResponse(response.Text, modeRaw, gradeLevel, personaResolved), nil
	}
	text = outputModeration.SanitizedText

	audioURL, ttsErr := s.tts.Render(ctx, text)
	audioStatus := AudioStatusUnavailable
	cues := avatar_cues.Cue{Emotion: "neutral"}
	if ttsErr == nil && strings.TrimSpace(audioURL) != "" {
		validatedAudioURL, audioErr := s.audioURLs.Validate(audioURL)
		if audioErr == nil {
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
	response = Response{
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
	if !providerFailed {
		outcome.SetResult(OutcomeSuccess, telemetryNone)
	}
	return response, nil
}

func assistantUnavailable() error {
	return apperrors.NotFound("assistant_unavailable", "assistant is not available")
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

func toContractVisemes(items []avatar_cues.Viseme) []Viseme {
	out := make([]Viseme, 0, len(items))
	for _, item := range items {
		out = append(out, Viseme{OffsetMs: item.OffsetMs, ID: item.ID, Weight: item.Weight})
	}
	return out
}
