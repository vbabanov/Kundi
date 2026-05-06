package profiles

import (
	"context"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/students"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

type Service struct {
	repo *students.Repository
}

func NewService(repo *students.Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) Get(ctx context.Context, studentID uuid.UUID) (students.Profile, error) {
	profile, err := s.repo.GetProfile(ctx, studentID)
	if err != nil {
		return students.Profile{}, apperrors.NotFound("profile_not_found", "student profile not found")
	}
	return profile, nil
}
