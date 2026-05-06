package moderation

import "strings"

type Decision struct {
	Allowed       bool
	SanitizedText string
	Reason        string
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Check(text string) Decision {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return Decision{
			Allowed:       false,
			SanitizedText: "",
			Reason:        "empty_input",
		}
	}

	lower := strings.ToLower(trimmed)
	blocked := []string{
		"kill yourself",
		"hurt yourself",
	}
	for _, token := range blocked {
		if strings.Contains(lower, token) {
			return Decision{
				Allowed:       false,
				SanitizedText: trimmed,
				Reason:        "safety_policy_triggered",
			}
		}
	}

	return Decision{
		Allowed:       true,
		SanitizedText: trimmed,
	}
}
