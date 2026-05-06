package jobhandlers

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/jobs"
)

type fakeEnqueuer struct {
	requests []jobs.EnqueueRequest
}

func (f *fakeEnqueuer) Enqueue(_ context.Context, req jobs.EnqueueRequest) (string, bool, error) {
	f.requests = append(f.requests, req)
	return "job-id", true, nil
}

type fakeAnalytics struct {
	dailyCalled  bool
	weeklyCalled bool
	staleCalled  bool
}

func (f *fakeAnalytics) RecomputeDailyStats(_ context.Context, _ uuid.UUID, _ time.Time) error {
	f.dailyCalled = true
	return nil
}
func (f *fakeAnalytics) RecomputeWeeklyStats(_ context.Context, _ uuid.UUID, _, _ time.Time) error {
	f.weeklyCalled = true
	return nil
}
func (f *fakeAnalytics) DetectStaleData(_ context.Context, _ uuid.UUID, _ time.Time, _ time.Duration) error {
	f.staleCalled = true
	return nil
}

type fakeDigestBuilder struct{}

func (fakeDigestBuilder) BuildHomeworkDigest(_ context.Context, _ uuid.UUID, _ time.Time, mode string) (string, error) {
	if mode == "topic" {
		return "topics-ready", nil
	}
	return "digest-ready", nil
}

func TestIngestPostProcessingEnqueuesFollowUpJobs(t *testing.T) {
	enq := &fakeEnqueuer{}
	analytics := &fakeAnalytics{}
	worker := NewJobsWorker(enq, analytics, fakeDigestBuilder{})
	studentID := uuid.New()

	err := worker.IngestPostProcessing(context.Background(), jobs.Job{
		Payload: map[string]any{
			"student_id": studentID.String(),
			"date":       "2026-03-30",
		},
	})
	if err != nil {
		t.Fatalf("ingest post-processing failed: %v", err)
	}
	if len(enq.requests) != 4 {
		t.Fatalf("expected 4 enqueued jobs, got %d", len(enq.requests))
	}
}

func TestGenerateParentDigestEnqueuesDispatch(t *testing.T) {
	enq := &fakeEnqueuer{}
	worker := NewJobsWorker(enq, &fakeAnalytics{}, fakeDigestBuilder{})
	studentID := uuid.New()

	err := worker.GenerateParentDigest(context.Background(), jobs.Job{
		Payload: map[string]any{
			"student_id": studentID.String(),
			"date":       "2026-03-30",
		},
	})
	if err != nil {
		t.Fatalf("generate parent digest failed: %v", err)
	}
	if len(enq.requests) != 1 {
		t.Fatalf("expected 1 enqueued job, got %d", len(enq.requests))
	}
	if enq.requests[0].Type != jobs.JobDispatchWhatsApp {
		t.Fatalf("expected dispatch job, got %s", enq.requests[0].Type)
	}
}

func TestStatsHandlersCallAnalytics(t *testing.T) {
	enq := &fakeEnqueuer{}
	analytics := &fakeAnalytics{}
	worker := NewJobsWorker(enq, analytics, fakeDigestBuilder{})
	studentID := uuid.New()

	if err := worker.RecomputeDailyStats(context.Background(), jobs.Job{
		Payload: map[string]any{
			"student_id": studentID.String(),
			"date":       "2026-03-30",
		},
	}); err != nil {
		t.Fatalf("daily handler failed: %v", err)
	}
	if err := worker.RecomputeWeeklyStats(context.Background(), jobs.Job{
		Payload: map[string]any{
			"student_id": studentID.String(),
			"week_start": "2026-03-30",
			"week_end":   "2026-04-05",
		},
	}); err != nil {
		t.Fatalf("weekly handler failed: %v", err)
	}
	if err := worker.DetectStaleData(context.Background(), jobs.Job{
		Payload: map[string]any{
			"student_id":    studentID.String(),
			"max_age_hours": 48,
		},
	}); err != nil {
		t.Fatalf("stale-data handler failed: %v", err)
	}

	if !analytics.dailyCalled || !analytics.weeklyCalled || !analytics.staleCalled {
		t.Fatalf("analytics handlers were not called as expected")
	}
}

func TestRecomputeDailyStatsMalformedDateReturnsPermanentError(t *testing.T) {
	worker := NewJobsWorker(&fakeEnqueuer{}, &fakeAnalytics{}, fakeDigestBuilder{})
	studentID := uuid.New()

	err := worker.RecomputeDailyStats(context.Background(), jobs.Job{
		Payload: map[string]any{
			"student_id": studentID.String(),
			"date":       "2026/03/30",
		},
	})
	if err == nil {
		t.Fatalf("expected malformed date error")
	}
	if !jobs.IsPermanent(err) {
		t.Fatalf("expected permanent error, got %v", err)
	}
}

func TestDetectStaleDataMalformedHoursReturnsPermanentError(t *testing.T) {
	worker := NewJobsWorker(&fakeEnqueuer{}, &fakeAnalytics{}, fakeDigestBuilder{})
	studentID := uuid.New()

	err := worker.DetectStaleData(context.Background(), jobs.Job{
		Payload: map[string]any{
			"student_id":    studentID.String(),
			"max_age_hours": "bad-value",
		},
	})
	if err == nil {
		t.Fatalf("expected malformed max_age_hours error")
	}
	if !jobs.IsPermanent(err) {
		t.Fatalf("expected permanent error, got %v", err)
	}
}
