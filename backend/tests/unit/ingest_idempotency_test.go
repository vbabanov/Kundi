package unit

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	ingest "github.com/kundi/kundi/backend/internal/modules/diary_ingest"
)

type fakeIngestRepo struct {
	created int
	merged  int
}

func (f *fakeIngestRepo) CreateBatch(_ context.Context, _ uuid.UUID, _ ingest.CanonicalIngestBundle, _ string) (uuid.UUID, bool, error) {
	f.created++
	if f.created == 1 {
		return uuid.New(), true, nil
	}
	return uuid.New(), false, nil
}

func (f *fakeIngestRepo) MergeBundle(_ context.Context, _ uuid.UUID, _ ingest.CanonicalIngestBundle) (int, int, error) {
	f.merged++
	return 3, 7, nil
}

func (f *fakeIngestRepo) MarkMerged(_ context.Context, _ uuid.UUID) error { return nil }

func TestIngestIdempotency(t *testing.T) {
	repo := &fakeIngestRepo{}
	svc := ingest.NewService(repo)

	bundle := ingest.CanonicalIngestBundle{
		Source:         "kundelik",
		IdempotencyKey: "bundle-key-1234",
		SyncedAt:       time.Now().UTC(),
		Lessons: []ingest.CanonicalLesson{
			{
				SourceLessonKey: "lesson-1",
				Date:            "2026-03-30",
				LessonNumber:    1,
				SubjectName:     "Math",
			},
		},
	}

	studentID := uuid.New()
	first, err := svc.IngestBundle(context.Background(), studentID, bundle)
	if err != nil {
		t.Fatalf("first ingest failed: %v", err)
	}
	if first.AlreadyProcessed {
		t.Fatalf("expected first ingest to be fresh")
	}

	second, err := svc.IngestBundle(context.Background(), studentID, bundle)
	if err != nil {
		t.Fatalf("second ingest failed: %v", err)
	}
	if !second.AlreadyProcessed {
		t.Fatalf("expected second ingest to be idempotent")
	}
	if repo.merged != 1 {
		t.Fatalf("merge must execute once, got %d", repo.merged)
	}
}
