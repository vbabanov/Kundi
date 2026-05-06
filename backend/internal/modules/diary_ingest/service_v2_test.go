package diary_ingest

import (
	"testing"
	"time"
)

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
