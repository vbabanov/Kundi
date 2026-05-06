package persona_policy

import "strings"

type Persona struct {
	Tone           string
	Style          string
	DefaultEmotion string
	DefaultGesture string
	GradeBand      string
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Resolve(mode string, gradeLevel int) Persona {
	band := gradeBand(gradeLevel)
	if strings.EqualFold(mode, "general_chat") {
		return Persona{
			Tone:           "friendly_companion",
			Style:          "conversational",
			DefaultEmotion: "friendly",
			DefaultGesture: "open_hand",
			GradeBand:      band,
		}
	}

	switch band {
	case "primary":
		return Persona{
			Tone:           "warm_playful",
			Style:          "short_steps_examples",
			DefaultEmotion: "encouraging",
			DefaultGesture: "explain",
			GradeBand:      band,
		}
	case "middle":
		return Persona{
			Tone:           "coach",
			Style:          "step_by_step",
			DefaultEmotion: "focused",
			DefaultGesture: "point",
			GradeBand:      band,
		}
	default:
		return Persona{
			Tone:           "mentor",
			Style:          "exam_oriented",
			DefaultEmotion: "confident",
			DefaultGesture: "explain",
			GradeBand:      band,
		}
	}
}

func gradeBand(gradeLevel int) string {
	if gradeLevel <= 0 {
		gradeLevel = 7
	}
	if gradeLevel <= 4 {
		return "primary"
	}
	if gradeLevel <= 8 {
		return "middle"
	}
	return "senior"
}
