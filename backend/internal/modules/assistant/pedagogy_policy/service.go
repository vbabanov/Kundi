package pedagogy_policy

import "strings"

type Flags struct {
	NeedsScaffold      bool
	ContainsHint       bool
	ContainsStepPlan   bool
	SafetyIntervention bool
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Resolve(mode string, userText string) Flags {
	flags := Flags{
		NeedsScaffold:      strings.EqualFold(mode, "tutor"),
		ContainsHint:       true,
		ContainsStepPlan:   strings.EqualFold(mode, "tutor"),
		SafetyIntervention: false,
	}
	if strings.TrimSpace(userText) == "" {
		flags.ContainsHint = false
		flags.ContainsStepPlan = false
	}
	return flags
}
