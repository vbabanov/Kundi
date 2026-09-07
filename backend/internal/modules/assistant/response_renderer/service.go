package response_renderer

import (
	"fmt"
	"strings"

	"github.com/kundi/kundi/backend/internal/modules/assistant/context_builder"
	"github.com/kundi/kundi/backend/internal/modules/assistant/persona_policy"
)

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Render(mode string, persona persona_policy.Persona, ctx context_builder.Context) string {
	question := strings.TrimSpace(ctx.UserQuestion)
	if question == "" {
		return "Please tell me what exactly you want to learn."
	}

	if strings.EqualFold(mode, "general_chat") {
		return fmt.Sprintf("I hear you. %s", question)
	}

	switch persona.GradeBand {
	case "1-2":
		return fmt.Sprintf("Let's take one simple step together: %s", question)
	case "3-4":
		return fmt.Sprintf("Here is a short explanation, one example, and a check: %s", question)
	case "5-7":
		return fmt.Sprintf("Let's work through this as a team while you make the key choices: %s", question)
	case "8-9":
		return fmt.Sprintf("Use the right terms and show a concise rationale for: %s", question)
	default:
		return fmt.Sprintf("Exam-focused walkthrough: %s", question)
	}
}
