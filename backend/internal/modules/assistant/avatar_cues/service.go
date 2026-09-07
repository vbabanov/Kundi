package avatar_cues

import "github.com/kundi/kundi/backend/internal/modules/assistant/persona_policy"

type Cue struct {
	Emotion   string
	Intensity float64
	Gesture   string
	Visemes   []Viseme
}

type Viseme struct {
	OffsetMs int
	ID       string
	Weight   float64
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Build(text string, persona persona_policy.Persona) Cue {
	visemes := []Viseme{
		{OffsetMs: 0, ID: "sil", Weight: 0.0},
		{OffsetMs: 120, ID: "A", Weight: 0.7},
		{OffsetMs: 260, ID: "E", Weight: 0.6},
		{OffsetMs: 420, ID: "O", Weight: 0.6},
	}
	if len(text) > 80 {
		visemes = append(visemes, Viseme{OffsetMs: 600, ID: "U", Weight: 0.5})
	}
	return Cue{
		Emotion:   persona.DefaultEmotion,
		Intensity: defaultIntensity(persona.DefaultEmotion),
		Gesture:   persona.DefaultGesture,
		Visemes:   visemes,
	}
}

func defaultIntensity(emotion string) float64 {
	switch emotion {
	case "joy":
		return 0.32
	case "fun":
		return 0.34
	case "surprised":
		return 0.18
	case "sorrow":
		return 0.24
	default:
		return 1.0
	}
}
