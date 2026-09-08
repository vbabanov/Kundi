package diary_ingest

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

type identityOnlyIngestRepository struct {
	batchID             uuid.UUID
	mergeCalls          int
	merged              CanonicalIngestBundleV2
	checksum            string
	created             bool
	existingAcademicIDs []string
}

func (r *identityOnlyIngestRepository) CreateBatch(_ context.Context, _ uuid.UUID, _ CanonicalIngestBundle, _ string) (uuid.UUID, bool, error) {
	return uuid.Nil, false, nil
}

func (r *identityOnlyIngestRepository) MergeBundle(_ context.Context, _ uuid.UUID, _ CanonicalIngestBundle) (int, int, error) {
	return 0, 0, nil
}

func (r *identityOnlyIngestRepository) MarkMerged(_ context.Context, _ uuid.UUID) error {
	return nil
}

func (r *identityOnlyIngestRepository) CreateBatchV2(_ context.Context, _ uuid.UUID, _ CanonicalIngestBundleV2, checksum string) (uuid.UUID, bool, error) {
	if r.created {
		if checksum != r.checksum {
			return r.batchID, false, ErrIdempotencyConflict
		}
		return r.batchID, false, nil
	}
	r.created = true
	r.checksum = checksum
	return r.batchID, true, nil
}

func (r *identityOnlyIngestRepository) MergeBundleV2(_ context.Context, _ uuid.UUID, bundle CanonicalIngestBundleV2) (MergeStatsV2, error) {
	r.mergeCalls++
	r.merged = bundle
	return MergeStatsV2{}, nil
}

func authoritativeEmptyBundleV2(idempotencyKey string) CanonicalIngestBundleV2 {
	return CanonicalIngestBundleV2{
		ContractVersion: 2,
		Source:          "kundelik",
		SourceAccount:   "student-account",
		IdempotencyKey:  idempotencyKey,
		SyncedAt:        time.Now().UTC(),
		Identity: CanonicalProviderIdentityV2{
			Provider:           "kundelik",
			ProviderAccountRef: "student-account",
			ProviderPersonID:   "person-1",
			ProviderSchoolID:   "school-1",
			ProviderGroupID:    "group-1",
			StudentFullName:    "Student",
		},
	}
}

func TestValidateBundleV2RejectsSpeculativeKinds(t *testing.T) {
	bundle := CanonicalIngestBundleV2{
		ContractVersion: 2,
		Source:          "kundelik",
		SourceAccount:   "a",
		IdempotencyKey:  "bundle-v2-key-001",
		SyncedAt:        time.Now().UTC(),
		Identity: CanonicalProviderIdentityV2{
			Provider: "kundelik",
		},
		Aggregates: []CanonicalAcademicAggregate{
			{
				ResultKind: "final_total",
				RecordedOn: "2026-03-11",
				ValueText:  "4",
				YearLabel:  "2025/2026",
			},
		},
	}
	if err := validateBundleV2(normalizeBundleV2(bundle)); err == nil {
		t.Fatalf("expected invalid aggregate kind error")
	}
}

func TestValidateBundleV2AcceptsBaselineKinds(t *testing.T) {
	termNo := 3
	bundle := CanonicalIngestBundleV2{
		ContractVersion: 2,
		Source:          "kundelik",
		SourceAccount:   "a",
		IdempotencyKey:  "bundle-v2-key-002",
		SyncedAt:        time.Now().UTC(),
		Identity: CanonicalProviderIdentityV2{
			Provider: "kundelik",
		},
		Results: []CanonicalAcademicResultV2{
			{
				ResultKind:   "regular",
				RecordedOn:   "2026-03-11",
				ValueText:    "8",
				LessonRefKey: "l-1",
			},
			{
				ResultKind: "sor",
				RecordedOn: "2026-03-11",
				ValueText:  "10/14",
				TermNo:     &termNo,
			},
			{
				ResultKind: "soch",
				RecordedOn: "2026-03-11",
				ValueText:  "18/30",
				TermNo:     &termNo,
			},
		},
		Aggregates: []CanonicalAcademicAggregate{
			{
				ResultKind: "term",
				TermNo:     &termNo,
				RecordedOn: "2026-03-11",
				ValueText:  "3",
			},
			{
				ResultKind: "year",
				YearLabel:  "2025/2026",
				RecordedOn: "2026-03-11",
				ValueText:  "3",
			},
		},
	}
	if err := validateBundleV2(normalizeBundleV2(bundle)); err != nil {
		t.Fatalf("expected bundle to be valid, got err=%v", err)
	}
}

func TestValidateBundleV2AcceptsIdentityOnlySnapshot(t *testing.T) {
	bundle := authoritativeEmptyBundleV2("bundle-v2-profile-only-001")

	if err := validateBundleV2(normalizeBundleV2(bundle)); err != nil {
		t.Fatalf("expected authenticated identity-only snapshot to be valid, got err=%v", err)
	}
}

func TestIngestBundleV2MergesIdentityOnlySnapshotIdempotentlyWithoutDeletingExistingRows(t *testing.T) {
	repo := &identityOnlyIngestRepository{
		batchID:             uuid.New(),
		existingAcademicIDs: []string{"lesson-before-window", "result-before-window"},
	}
	service := NewService(repo)
	bundle := authoritativeEmptyBundleV2("bundle-v2-profile-only-002")
	bundle.Identity.ProviderPersonID = "person-2"
	studentID := uuid.New()

	result, err := service.IngestBundleV2(context.Background(), studentID, bundle)
	if err != nil {
		t.Fatalf("expected identity-only ingest to succeed, got err=%v", err)
	}
	if result.BatchID != repo.batchID.String() {
		t.Fatalf("expected batch_id %q, got %q", repo.batchID, result.BatchID)
	}
	if repo.mergeCalls != 1 {
		t.Fatalf("expected one identity-only merge, got %d", repo.mergeCalls)
	}
	if repo.merged.Identity.ProviderPersonID != "person-2" {
		t.Fatalf("expected provider person identity to reach merge, got %q", repo.merged.Identity.ProviderPersonID)
	}
	second, err := service.IngestBundleV2(context.Background(), studentID, bundle)
	if err != nil {
		t.Fatalf("expected identity-only replay to succeed, got err=%v", err)
	}
	if !second.AlreadyProcessed {
		t.Fatal("expected identity-only replay to remain idempotent")
	}
	if repo.mergeCalls != 1 {
		t.Fatalf("expected exactly one merge after replay, got %d", repo.mergeCalls)
	}
	if len(repo.existingAcademicIDs) != 2 || repo.existingAcademicIDs[0] != "lesson-before-window" || repo.existingAcademicIDs[1] != "result-before-window" {
		t.Fatalf("identity-only merge must not delete existing academic rows, got %#v", repo.existingAcademicIDs)
	}
}

func TestValidateBundleV2RejectsNonAuthoritativeAcademicEmptySnapshots(t *testing.T) {
	tests := []struct {
		name   string
		mutate func(*CanonicalIngestBundleV2)
	}{
		{name: "missing source account", mutate: func(bundle *CanonicalIngestBundleV2) { bundle.SourceAccount = "" }},
		{name: "missing provider account", mutate: func(bundle *CanonicalIngestBundleV2) { bundle.Identity.ProviderAccountRef = "" }},
		{name: "account mismatch", mutate: func(bundle *CanonicalIngestBundleV2) { bundle.Identity.ProviderAccountRef = "other-account" }},
		{name: "missing person", mutate: func(bundle *CanonicalIngestBundleV2) { bundle.Identity.ProviderPersonID = "" }},
		{name: "missing school", mutate: func(bundle *CanonicalIngestBundleV2) { bundle.Identity.ProviderSchoolID = "" }},
		{name: "missing group", mutate: func(bundle *CanonicalIngestBundleV2) { bundle.Identity.ProviderGroupID = "" }},
		{name: "missing sync time", mutate: func(bundle *CanonicalIngestBundleV2) { bundle.SyncedAt = time.Time{} }},
		{name: "provider without authoritative empty support", mutate: func(bundle *CanonicalIngestBundleV2) {
			bundle.Source = "dnevnikru"
			bundle.Identity.Provider = "dnevnikru"
		}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			bundle := authoritativeEmptyBundleV2("bundle-v2-empty-001")
			tt.mutate(&bundle)
			err := validateBundleV2(normalizeBundleV2(bundle))
			if !apperrors.Is(err, "empty_bundle_not_authoritative") {
				t.Fatalf("expected empty_bundle_not_authoritative, got %v", err)
			}
		})
	}
}

func TestValidateBundleV2RejectsProviderSourceMismatchForAcademicEmptySnapshot(t *testing.T) {
	bundle := authoritativeEmptyBundleV2("bundle-v2-empty-mismatch-001")
	bundle.Identity.Provider = "dnevnikru"

	err := validateBundleV2(normalizeBundleV2(bundle))
	if !apperrors.Is(err, "provider_source_mismatch") {
		t.Fatalf("expected provider_source_mismatch, got %v", err)
	}
}

func TestSyntheticResultFingerprintUsesRichIdentity(t *testing.T) {
	a := buildSyntheticResultEvidence("kundelik", "person-1", CanonicalAcademicResultV2{
		ResultKind:        "regular",
		ProviderSubjectID: "subj-1",
		ProviderWorkID:    "work-1",
		ProviderMarkID:    "mark-1",
		SourceResultKey:   "res-1",
		ValueText:         "8",
		RecordedOn:        "2026-03-11",
		LessonRefKey:      "lesson-a",
	})
	b := buildSyntheticResultEvidence("kundelik", "person-1", CanonicalAcademicResultV2{
		ResultKind:        "regular",
		ProviderSubjectID: "subj-1",
		ProviderWorkID:    "work-2",
		ProviderMarkID:    "mark-1",
		SourceResultKey:   "res-1",
		ValueText:         "8",
		RecordedOn:        "2026-03-11",
		LessonRefKey:      "lesson-a",
	})
	if a.FingerprintSHA256 == b.FingerprintSHA256 {
		t.Fatalf("expected different fingerprints for different provider_work_id")
	}
}

func TestNormalizeBundleV2KeepsAttendanceMatchingKeys(t *testing.T) {
	bundle := CanonicalIngestBundleV2{
		ContractVersion: 2,
		Source:          "kundelik",
		SourceAccount:   "a",
		IdempotencyKey:  "bundle-v2-key-003",
		SyncedAt:        time.Now().UTC(),
		Identity: CanonicalProviderIdentityV2{
			Provider: "kundelik",
		},
		Lessons: []CanonicalLessonV2{
			{
				SourceLessonKey:   "lesson-1",
				ProviderLessonID:  "lesson-1",
				ProviderSubjectID: "sub-math",
				Date:              "2026-04-07",
				LessonNumber:      2,
				SubjectName:       "Algebra",
			},
		},
		Attendance: []CanonicalAttendanceEventV2{
			{
				SourceEventKey:    "att-1",
				ProviderEventKey:  "att-1",
				ProviderLessonRef: "lesson-1",
				ProviderSubjectID: "sub-math",
				SubjectName:       "Algebra",
				LessonNumber:      2,
				RecordedOn:        "2026-04-07",
				RawCode:           "Н",
				NormalizedStatus:  "absent",
			},
		},
	}

	normalized := normalizeBundleV2(bundle)
	if len(normalized.Attendance) != 1 {
		t.Fatalf("expected 1 attendance item, got %d", len(normalized.Attendance))
	}
	item := normalized.Attendance[0]
	if item.ProviderSubjectID != "sub-math" {
		t.Fatalf("expected provider_subject_id to be preserved, got %q", item.ProviderSubjectID)
	}
	if item.SubjectName != "Algebra" {
		t.Fatalf("expected subject_name to be preserved, got %q", item.SubjectName)
	}
	if item.LessonNumber != 2 {
		t.Fatalf("expected lesson_number to be preserved, got %d", item.LessonNumber)
	}
}
