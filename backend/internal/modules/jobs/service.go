package jobs

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/kundi/kundi/backend/internal/platform/apperrors"
	"github.com/kundi/kundi/backend/internal/platform/validate"
)

type Handler func(ctx context.Context, job Job) error

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) Enqueue(ctx context.Context, req EnqueueRequest) (string, bool, error) {
	if req.Type == "" {
		return "", false, apperrors.BadRequest("job_type_required", "job type is required")
	}
	if !validate.IdempotencyKey(req.IdempotencyKey) {
		return "", false, apperrors.BadRequest("job_idempotency_invalid", "job idempotency key is invalid")
	}
	if req.Priority <= 0 {
		req.Priority = 50
	}
	return s.repo.Enqueue(ctx, req)
}

func (s *Service) RunLoop(ctx context.Context, workerName string, leaseDuration, pollInterval time.Duration, handlers map[JobType]Handler) error {
	if workerName == "" {
		return errors.New("worker name is required")
	}
	if pollInterval <= 0 {
		pollInterval = 700 * time.Millisecond
	}
	if leaseDuration <= 0 {
		leaseDuration = 45 * time.Second
	}
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			job, err := s.repo.LeaseNext(ctx, workerName, leaseDuration)
			if err != nil {
				if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
					return err
				}
				time.Sleep(pollInterval)
				continue
			}
			if job == nil {
				time.Sleep(pollInterval)
				continue
			}
			h, ok := handlers[job.Type]
			if !ok {
				_, _ = s.repo.Fail(ctx, job.ID, workerName, errors.New("unsupported job type"))
				continue
			}
			if err := h(ctx, *job); err != nil {
				_, _ = s.repo.Fail(ctx, job.ID, workerName, err)
				continue
			}
			if err := s.repo.Complete(ctx, job.ID); err != nil {
				_, _ = s.repo.Fail(ctx, job.ID, workerName, err)
			}
		}
	}
}

func (s *Service) GetStatus(ctx context.Context, jobID string) (*JobStatusRecord, error) {
	trimmedID := strings.TrimSpace(jobID)
	if trimmedID == "" {
		return nil, apperrors.BadRequest("job_id_required", "job id is required")
	}
	return s.repo.GetStatus(ctx, trimmedID)
}
