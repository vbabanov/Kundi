package persona

import (
	"context"

	"github.com/google/uuid"
)

type Profile struct {
	ToneProfile  string
	StyleProfile string
	GradeLevel   int
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Resolve(_ context.Context, _ uuid.UUID, gradeLevel int) Profile {
	switch {
	case gradeLevel <= 2:
		return Profile{ToneProfile: "calm_companion", StyleProfile: "one_simple_step", GradeLevel: gradeLevel}
	case gradeLevel <= 4:
		return Profile{ToneProfile: "warm_guide", StyleProfile: "short_example_check", GradeLevel: gradeLevel}
	case gradeLevel <= 7:
		return Profile{ToneProfile: "friendly_coach", StyleProfile: "guided_independence", GradeLevel: gradeLevel}
	case gradeLevel <= 9:
		return Profile{ToneProfile: "respectful_coach", StyleProfile: "terms_and_reasoning", GradeLevel: gradeLevel}
	default:
		return Profile{ToneProfile: "mentor", StyleProfile: "strategy_argument_exam", GradeLevel: gradeLevel}
	}
}
