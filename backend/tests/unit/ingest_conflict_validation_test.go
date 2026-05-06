package unit

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	ingest "github.com/kundi/kundi/backend/internal/modules/diary_ingest"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

type conflictIngestRepo struct{}

func (conflictIngestRepo) CreateBatch(_ context.Context, _ uuid.UUID, _ ingest.CanonicalIngestBundle, _ string) (uuid.UUID, bool, error) {
	return uuid.New(), false, ingest.ErrIdempotencyConflict
}
func (conflictIngestRepo) MergeBundle(_ context.Context, _ uuid.UUID, _ ingest.CanonicalIngestBundle) (int, int, error) {
	return 0, 0, nil
}
func (conflictIngestRepo) MarkMerged(_ context.Context, _ uuid.UUID) error { return nil }

func TestIngestReturnsConflictOnIdempotencyChecksumMismatch(t *testing.T) {
	svc := ingest.NewService(conflictIngestRepo{})
	_, err := svc.IngestBundle(context.Background(), uuid.New(), ingest.CanonicalIngestBundle{
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
	})
	if err == nil {
		t.Fatalf("expected conflict error")
	}
	if !apperrors.Is(err, "ingest_idempotency_conflict") {
		t.Fatalf("expected ingest_idempotency_conflict, got %v", err)
	}
}

type noopIngestRepo struct{}

func (noopIngestRepo) CreateBatch(_ context.Context, _ uuid.UUID, _ ingest.CanonicalIngestBundle, _ string) (uuid.UUID, bool, error) {
	return uuid.New(), true, nil
}
func (noopIngestRepo) MergeBundle(_ context.Context, _ uuid.UUID, _ ingest.CanonicalIngestBundle) (int, int, error) {
	return 0, 0, nil
}
func (noopIngestRepo) MarkMerged(_ context.Context, _ uuid.UUID) error { return nil }

func TestIngestRejectsInvalidAttendanceCode(t *testing.T) {
	svc := ingest.NewService(noopIngestRepo{})
	_, err := svc.IngestBundle(context.Background(), uuid.New(), ingest.CanonicalIngestBundle{
		Source:         "kundelik",
		IdempotencyKey: "bundle-key-1234",
		SyncedAt:       time.Now().UTC(),
		Attendance: []ingest.AttendanceEvent{
			{Date: "2026-03-30", Code: "bad"},
		},
	})
	if err == nil {
		t.Fatalf("expected validation error")
	}
	if !apperrors.Is(err, "invalid_attendance_code") {
		t.Fatalf("expected invalid_attendance_code, got %v", err)
	}
}
