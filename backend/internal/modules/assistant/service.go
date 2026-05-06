package assistant

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/avatar_cues"
	"github.com/kundi/kundi/backend/internal/modules/assistant/context_builder"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/moderation"
	"github.com/kundi/kundi/backend/internal/modules/assistant/pedagogy_policy"
	"github.com/kundi/kundi/backend/internal/modules/assistant/persona_policy"
	"github.com/kundi/kundi/backend/internal/modules/assistant/response_renderer"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tts"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

type Service struct {
	personaLegacy *persona.Service
	context       *context_builder.Service
	personaPolicy *persona_policy.Service
	pedagogy      *pedagogy_policy.Service
	moderation    *moderation.Service
	renderer      *response_renderer.Service
	llm           llm.Provider
	tts           tts.Provider
	avatarCues    *avatar_cues.Service
}

func NewService(personaService *persona.Service, llmProvider llm.Provider, ttsProvider tts.Provider) *Service {
	if llmProvider == nil {
		llmProvider = llm.NewDeterministicProvider()
	}
	if ttsProvider == nil {
		ttsProvider = tts.NewService("")
	}
	return &Service{
		personaLegacy: personaService,
		context:       context_builder.NewService(),
		personaPolicy: persona_policy.NewService(),
		pedagogy:      pedagogy_policy.NewService(),
		moderation:    moderation.NewService(),
		renderer:      response_renderer.NewService(),
		llm:           llmProvider,
		tts:           ttsProvider,
		avatarCues:    avatar_cues.NewService(),
	}
}

func (s *Service) Message(ctx context.Context, cmd MessageCommand) (Response, error) {
	if strings.TrimSpace(cmd.Text) == "" {
		return Response{}, apperrors.BadRequest("assistant_empty_text", "assistant text is required")
	}
	if cmd.Mode != ModeTutor && cmd.Mode != ModeGeneralChat {
		cmd.Mode = ModeTutor
	}

	studentID, err := uuid.Parse(strings.TrimSpace(cmd.StudentID))
	if err != nil {
		return Response{}, apperrors.BadRequest("assistant_student_id_invalid", "student id is invalid")
	}

	gradeLevel := cmd.GradeLevel
	if gradeLevel <= 0 {
		gradeLevel = 7
	}
	legacyPersona := s.personaLegacy.Resolve(ctx, studentID, gradeLevel)

	modDecision := s.moderation.Check(cmd.Text)
	if !modDecision.Allowed {
		return Response{}, apperrors.BadRequest("assistant_moderation_blocked", "message is blocked by safety policy")
	}

	history := make([]context_builder.ChatRecord, 0, len(cmd.History))
	for _, record := range cmd.History {
		history = append(history, context_builder.ChatRecord{
			Role: record.Role,
			Text: record.Text,
		})
	}
	builtContext := s.context.Build(context_builder.Input{
		Text:    modDecision.SanitizedText,
		History: history,
	})

	modeRaw := string(cmd.Mode)
	personaResolved := s.personaPolicy.Resolve(modeRaw, gradeLevel)
	if strings.TrimSpace(legacyPersona.ToneProfile) != "" {
		personaResolved.Tone = strings.TrimSpace(legacyPersona.ToneProfile)
	}
	if strings.TrimSpace(legacyPersona.StyleProfile) != "" {
		personaResolved.Style = strings.TrimSpace(legacyPersona.StyleProfile)
	}
	pedagogy := s.pedagogy.Resolve(modeRaw, modDecision.SanitizedText)

	renderedText := s.renderer.Render(modeRaw, personaResolved, builtContext)
	llmResponse, llmErr := s.llm.Generate(ctx, llm.Request{
		Mode:        modeRaw,
		Prompt:      renderedText,
		PersonaTone: personaResolved.Tone,
		Style:       personaResolved.Style,
		History:     builtContext.RecentUserMessages,
	})
	text := strings.TrimSpace(llmResponse.Text)
	if llmErr != nil || text == "" {
		if llmErr != nil && !errors.Is(llmErr, context.Canceled) {
			pedagogy.SafetyIntervention = true
		}
		text = renderedText
	}

	audioURL, ttsErr := s.tts.Render(ctx, text)
	audioStatus := AudioStatusReady
	cues := s.avatarCues.Build(text, personaResolved)
	if ttsErr != nil || strings.TrimSpace(audioURL) == "" {
		audioStatus = AudioStatusUnavailable
		audioURL = ""
		cues = avatar_cues.Cue{
			Emotion: "neutral",
			Gesture: "",
			Visemes: nil,
		}
	}

	gestureTags := make([]string, 0, 1)
	if cues.Gesture != "" {
		gestureTags = append(gestureTags, cues.Gesture)
	}

	return Response{
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
		Behavior: BehaviorMeta{
			Mode:         modeRaw,
			GradeLevel:   gradeLevel,
			GradeBand:    personaResolved.GradeBand,
			PersonaTone:  personaResolved.Tone,
			PersonaStyle: personaResolved.Style,
		},
	}, nil
}

func toContractVisemes(items []avatar_cues.Viseme) []Viseme {
	out := make([]Viseme, 0, len(items))
	for _, item := range items {
		out = append(out, Viseme{
			OffsetMs: item.OffsetMs,
			ID:       item.ID,
			Weight:   item.Weight,
		})
	}
	return out
}
