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
	case "primary":
		return fmt.Sprintf("Let's solve it together in small steps: %s", question)
	case "middle":
		return fmt.Sprintf("Step-by-step plan for this task: %s", question)
	default:
		return fmt.Sprintf("Exam-focused walkthrough: %s", question)
	}
}
