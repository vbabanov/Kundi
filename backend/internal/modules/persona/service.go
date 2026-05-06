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
	if gradeLevel <= 4 {
		return Profile{ToneProfile: "warm_playful", StyleProfile: "simple_examples", GradeLevel: gradeLevel}
	}
	if gradeLevel <= 8 {
		return Profile{ToneProfile: "energetic_coach", StyleProfile: "step_by_step", GradeLevel: gradeLevel}
	}
	return Profile{ToneProfile: "mentor", StyleProfile: "exam_oriented", GradeLevel: gradeLevel}
}
