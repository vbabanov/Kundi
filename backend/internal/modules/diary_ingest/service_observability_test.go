package diary_ingest

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/platform/observability"
)

type metricsRecorder struct {
	incrNames    []string
	observeNames []string
}

func (m *metricsRecorder) Incr(name string, _ map[string]string) {
	m.incrNames = append(m.incrNames, name)
}

func (m *metricsRecorder) Observe(name string, _ float64, _ map[string]string) {
	m.observeNames = append(m.observeNames, name)
}

type tracerRecorder struct {
	spans []string
}

func (t *tracerRecorder) Start(ctx context.Context, spanName string) (context.Context, func(error)) {
	t.spans = append(t.spans, spanName)
	return ctx, func(error) {}
}

type fakeIngestRepoObserve struct {
	createErr error
	mergeErr  error
	inserted  bool
}

func (f fakeIngestRepoObserve) CreateBatch(_ context.Context, _ uuid.UUID, _ CanonicalIngestBundle, _ string) (uuid.UUID, bool, error) {
	if f.createErr != nil {
		return uuid.Nil, false, f.createErr
	}
	if f.inserted {
		return uuid.New(), true, nil
	}
	return uuid.New(), false, nil
}

func (f fakeIngestRepoObserve) MergeBundle(_ context.Context, _ uuid.UUID, _ CanonicalIngestBundle) (int, int, error) {
	if f.mergeErr != nil {
		return 0, 0, f.mergeErr
	}
	return 2, 3, nil
}

func (f fakeIngestRepoObserve) MarkMerged(_ context.Context, _ uuid.UUID) error {
	return nil
}

func TestIngestBundleEmitsObservabilityHooks(t *testing.T) {
	metrics := &metricsRecorder{}
	tracer := &tracerRecorder{}
	svc := NewService(fakeIngestRepoObserve{inserted: true}, observability.Hooks{Metrics: metrics, Tracer: tracer})

	bundle := CanonicalIngestBundle{
		Source:         "kundelik",
		IdempotencyKey: "bundle-key-1234",
		SyncedAt:       time.Now().UTC(),
		Lessons: []CanonicalLesson{{
			SourceLessonKey: "lesson-1",
			Date:            "2026-04-12",
			LessonNumber:    0,
			SubjectName:     "Math",
		}},
	}

	_, err := svc.IngestBundle(context.Background(), uuid.New(), bundle)
	if err != nil {
		t.Fatalf("ingest failed: %v", err)
	}
	assertContainsMetric(t, metrics.incrNames, "backend.ingest.requests_total")
	assertContainsMetric(t, metrics.incrNames, "backend.ingest.success_total")
	assertContainsMetric(t, metrics.observeNames, "backend.ingest.latency_ms")
	if len(tracer.spans) == 0 || tracer.spans[0] != "ingest.bundle.v1" {
		t.Fatalf("expected ingest v1 span, got %v", tracer.spans)
	}
}

func TestIngestBundleV2EmitsFailureHooks(t *testing.T) {
	metrics := &metricsRecorder{}
	tracer := &tracerRecorder{}
	svc := NewService(fakeIngestRepoObserve{inserted: true}, observability.Hooks{Metrics: metrics, Tracer: tracer})

	bundle := CanonicalIngestBundleV2{
		ContractVersion: 2,
		Source:          "kundelik",
		SourceAccount:   "demo-account",
		IdempotencyKey:  "bundle-v2-key-001",
		SyncedAt:        time.Now().UTC(),
		Identity: CanonicalProviderIdentityV2{
			Provider: "kundelik",
		},
		Lessons: []CanonicalLessonV2{{
			SourceLessonKey: "l-1",
			Date:            "2026-04-12",
			LessonNumber:    0,
			SubjectName:     "Math",
		}},
	}

	_, err := svc.IngestBundleV2(context.Background(), uuid.New(), bundle)
	if err == nil {
		t.Fatalf("expected v2 ingest failure for missing RepositoryV2")
	}
	assertContainsMetric(t, metrics.incrNames, "backend.ingest.requests_total")
	assertContainsMetric(t, metrics.incrNames, "backend.ingest.failure_total")
	assertContainsMetric(t, metrics.observeNames, "backend.ingest.latency_ms")
	if len(tracer.spans) == 0 || tracer.spans[0] != "ingest.bundle.v2" {
		t.Fatalf("expected ingest v2 span, got %v", tracer.spans)
	}
}

func TestClassifyErrorClass(t *testing.T) {
	err := classifyErrorClass(errors.New("boom"))
	if err != "internal" {
		t.Fatalf("expected internal, got %s", err)
	}
}

func assertContainsMetric(t *testing.T, names []string, expected string) {
	t.Helper()
	for _, name := range names {
		if name == expected {
			return
		}
	}
	t.Fatalf("expected metric %s in %v", expected, names)
}
