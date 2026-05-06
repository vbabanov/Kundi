package unit

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/kundi/kundi/backend/internal/modules/jobs"
)

type fakeJobsRepo struct {
	leased    bool
	failed    int
	completed int
	failMode  bool
}

func (f *fakeJobsRepo) Enqueue(_ context.Context, _ jobs.EnqueueRequest) (string, bool, error) {
	return "job-id", true, nil
}

func (f *fakeJobsRepo) LeaseNext(_ context.Context, _ string, _ time.Duration) (*jobs.Job, error) {
	if f.leased {
		return nil, nil
	}
	f.leased = true
	return &jobs.Job{ID: "job-id", Type: jobs.JobAIPostProcessing, IdempotencyKey: "job-key-1"}, nil
}

func (f *fakeJobsRepo) Complete(_ context.Context, _ string) error {
	f.completed++
	return nil
}

func (f *fakeJobsRepo) Fail(_ context.Context, _ string, _ string, _ error) (bool, error) {
	f.failed++
	return false, nil
}

func (f *fakeJobsRepo) GetStatus(_ context.Context, _ string) (*jobs.JobStatusRecord, error) {
	return nil, nil
}

func TestJobsRetryFlow(t *testing.T) {
	repo := &fakeJobsRepo{}
	svc := jobs.NewService(repo)

	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
	defer cancel()

	handlers := map[jobs.JobType]jobs.Handler{
		jobs.JobAIPostProcessing: func(_ context.Context, _ jobs.Job) error {
			return errors.New("boom")
		},
	}

	_ = svc.RunLoop(ctx, "worker-ai-test", 5*time.Second, 10*time.Millisecond, handlers)

	if repo.failed != 1 {
		t.Fatalf("expected one failed attempt, got %d", repo.failed)
	}
	if repo.completed != 0 {
		t.Fatalf("expected zero completed jobs, got %d", repo.completed)
	}
}

func TestJobsSuccessFlow(t *testing.T) {
	repo := &fakeJobsRepo{}
	svc := jobs.NewService(repo)

	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
	defer cancel()

	handlers := map[jobs.JobType]jobs.Handler{
		jobs.JobAIPostProcessing: func(_ context.Context, _ jobs.Job) error {
			return nil
		},
	}

	_ = svc.RunLoop(ctx, "worker-ai-test", 5*time.Second, 10*time.Millisecond, handlers)

	if repo.failed != 0 {
		t.Fatalf("expected zero failed attempts, got %d", repo.failed)
	}
	if repo.completed != 1 {
		t.Fatalf("expected one completed job, got %d", repo.completed)
	}
}
