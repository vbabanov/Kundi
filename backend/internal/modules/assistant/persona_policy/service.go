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
			Tone:           generalChatTone(band),
			Style:          generalChatStyle(band),
			DefaultEmotion: "fun",
			DefaultGesture: "open_hand",
			GradeBand:      band,
		}
	}

	switch band {
	case "1-2":
		return Persona{
			Tone:           "calm_companion",
			Style:          "one_simple_step",
			DefaultEmotion: "joy",
			DefaultGesture: "explain",
			GradeBand:      band,
		}
	case "3-4":
		return Persona{
			Tone:           "warm_guide",
			Style:          "short_example_check",
			DefaultEmotion: "joy",
			DefaultGesture: "explain",
			GradeBand:      band,
		}
	case "5-7":
		return Persona{
			Tone:           "friendly_coach",
			Style:          "guided_independence",
			DefaultEmotion: "neutral",
			DefaultGesture: "point",
			GradeBand:      band,
		}
	case "8-9":
		return Persona{
			Tone:           "respectful_coach",
			Style:          "terms_and_reasoning",
			DefaultEmotion: "surprised",
			DefaultGesture: "point",
			GradeBand:      band,
		}
	default:
		return Persona{
			Tone:           "mentor",
			Style:          "strategy_argument_exam",
			DefaultEmotion: "neutral",
			DefaultGesture: "explain",
			GradeBand:      band,
		}
	}
}

func gradeBand(gradeLevel int) string {
	if gradeLevel <= 0 {
		gradeLevel = 7
	}
	if gradeLevel <= 2 {
		return "1-2"
	}
	if gradeLevel <= 4 {
		return "3-4"
	}
	if gradeLevel <= 7 {
		return "5-7"
	}
	if gradeLevel <= 9 {
		return "8-9"
	}
	return "10-11"
}

func generalChatTone(band string) string {
	if band == "10-11" || band == "8-9" {
		return "respectful_companion"
	}
	return "friendly_companion"
}

func generalChatStyle(band string) string {
	switch band {
	case "1-2":
		return "simple_conversation"
	case "3-4":
		return "short_conversation"
	case "5-7":
		return "natural_conversation"
	default:
		return "concise_peer_conversation"
	}
}
