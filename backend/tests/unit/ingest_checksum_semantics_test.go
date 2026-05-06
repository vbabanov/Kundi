package unit

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	ingest "github.com/kundi/kundi/backend/internal/modules/diary_ingest"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

type checksumAwareIngestRepo struct {
	checksums map[string]string
	merged    int
}

func newChecksumAwareIngestRepo() *checksumAwareIngestRepo {
	return &checksumAwareIngestRepo{
		checksums: make(map[string]string),
	}
}

func (r *checksumAwareIngestRepo) CreateBatch(_ context.Context, studentID uuid.UUID, bundle ingest.CanonicalIngestBundle, checksum string) (uuid.UUID, bool, error) {
	key := studentID.String() + ":" + bundle.IdempotencyKey
	if existing, ok := r.checksums[key]; ok {
		if existing != checksum {
			return uuid.New(), false, ingest.ErrIdempotencyConflict
		}
		return uuid.New(), false, nil
	}
	r.checksums[key] = checksum
	return uuid.New(), true, nil
}

func (r *checksumAwareIngestRepo) MergeBundle(_ context.Context, _ uuid.UUID, _ ingest.CanonicalIngestBundle) (int, int, error) {
	r.merged++
	return 1, 1, nil
}

func (r *checksumAwareIngestRepo) MarkMerged(_ context.Context, _ uuid.UUID) error { return nil }

func TestIngestSamePayloadWithoutSyncedAtRemainsIdempotent(t *testing.T) {
	repo := newChecksumAwareIngestRepo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()

	bundle := checksumSemanticBundle("idem-key-1", "Math")
	first, err := svc.IngestBundle(context.Background(), studentID, bundle)
	if err != nil {
		t.Fatalf("first ingest failed: %v", err)
	}
	if first.AlreadyProcessed {
		t.Fatalf("expected first ingest not processed")
	}

	time.Sleep(10 * time.Millisecond)
	second, err := svc.IngestBundle(context.Background(), studentID, bundle)
	if err != nil {
		t.Fatalf("second ingest failed: %v", err)
	}
	if !second.AlreadyProcessed {
		t.Fatalf("expected second ingest already processed")
	}
	if repo.merged != 1 {
		t.Fatalf("expected one merge execution, got %d", repo.merged)
	}
}

func TestIngestSameIdempotencyDifferentPayloadConflicts(t *testing.T) {
	repo := newChecksumAwareIngestRepo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()

	if _, err := svc.IngestBundle(context.Background(), studentID, checksumSemanticBundle("idem-key-2", "Math")); err != nil {
		t.Fatalf("first ingest failed: %v", err)
	}
	_, err := svc.IngestBundle(context.Background(), studentID, checksumSemanticBundle("idem-key-2", "History"))
	if err == nil {
		t.Fatalf("expected conflict for same idempotency and different payload")
	}
	if !apperrors.Is(err, "ingest_idempotency_conflict") {
		t.Fatalf("expected ingest_idempotency_conflict, got %v", err)
	}
}

func TestIngestRetryWithoutExplicitSyncedAtDoesNotConflict(t *testing.T) {
	repo := newChecksumAwareIngestRepo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()

	firstPayload := checksumSemanticBundle("idem-key-3", "Physics")
	if _, err := svc.IngestBundle(context.Background(), studentID, firstPayload); err != nil {
		t.Fatalf("first ingest failed: %v", err)
	}

	time.Sleep(10 * time.Millisecond)
	retryPayload := checksumSemanticBundle("idem-key-3", "Physics")
	second, err := svc.IngestBundle(context.Background(), studentID, retryPayload)
	if err != nil {
		t.Fatalf("retry ingest must not conflict: %v", err)
	}
	if !second.AlreadyProcessed {
		t.Fatalf("expected retry payload to resolve as already processed")
	}
}

func checksumSemanticBundle(idempotencyKey string, subject string) ingest.CanonicalIngestBundle {
	return ingest.CanonicalIngestBundle{
		Source:         "kundelik",
		SourceAccount:  "student-login",
		IdempotencyKey: idempotencyKey,
		Lessons: []ingest.CanonicalLesson{
			{
				SourceLessonKey: "lesson-1",
				Date:            "2026-03-30",
				LessonNumber:    1,
				SubjectName:     subject,
				Homework: ingest.HomeworkPayload{
					SourceHomeworkKey: "hw-1",
					Description:       "Solve 1-10",
				},
				Grades: []ingest.GradePayload{
					{SourceGradeKey: "g-1", Value: "5", Type: "regular"},
				},
			},
		},
	}
}
