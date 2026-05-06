package unit

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	ingest "github.com/kundi/kundi/backend/internal/modules/diary_ingest"
)

type memoryIngestRepo struct {
	checksums map[string]string
	merges    int
}

func newMemoryIngestRepo() *memoryIngestRepo {
	return &memoryIngestRepo{
		checksums: make(map[string]string),
	}
}

func (m *memoryIngestRepo) CreateBatch(_ context.Context, _ uuid.UUID, bundle ingest.CanonicalIngestBundle, checksum string) (uuid.UUID, bool, error) {
	if existing, ok := m.checksums[bundle.IdempotencyKey]; ok {
		if existing != checksum {
			return uuid.New(), false, ingest.ErrIdempotencyConflict
		}
		return uuid.New(), false, nil
	}
	m.checksums[bundle.IdempotencyKey] = checksum
	return uuid.New(), true, nil
}

func (m *memoryIngestRepo) MergeBundle(_ context.Context, _ uuid.UUID, _ ingest.CanonicalIngestBundle) (int, int, error) {
	m.merges++
	return 1, 1, nil
}

func (m *memoryIngestRepo) MarkMerged(_ context.Context, _ uuid.UUID) error { return nil }

func TestOverlappingWindowsWithDifferentIdempotencyMergeTwice(t *testing.T) {
	repo := newMemoryIngestRepo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()

	first := ingest.CanonicalIngestBundle{
		Source:         "kundelik",
		IdempotencyKey: "window-key-20260330",
		SyncedAt:       time.Now().UTC(),
		Lessons: []ingest.CanonicalLesson{
			{SourceLessonKey: "lesson-1", Date: "2026-03-30", LessonNumber: 1, SubjectName: "Math"},
		},
	}
	second := ingest.CanonicalIngestBundle{
		Source:         "kundelik",
		IdempotencyKey: "window-key-20260331",
		SyncedAt:       time.Now().UTC(),
		Lessons: []ingest.CanonicalLesson{
			{SourceLessonKey: "lesson-1", Date: "2026-03-30", LessonNumber: 1, SubjectName: "Math"},
			{SourceLessonKey: "lesson-2", Date: "2026-03-31", LessonNumber: 2, SubjectName: "History"},
		},
	}

	if _, err := svc.IngestBundle(context.Background(), studentID, first); err != nil {
		t.Fatalf("first window ingest failed: %v", err)
	}
	if _, err := svc.IngestBundle(context.Background(), studentID, second); err != nil {
		t.Fatalf("second window ingest failed: %v", err)
	}
	if repo.merges != 2 {
		t.Fatalf("expected two merge executions for two idempotency keys, got %d", repo.merges)
	}
}
