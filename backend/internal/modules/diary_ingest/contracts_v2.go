package diary_ingest

import "time"

type AcademicEventResultKind string

const (
	EventResultKindRegular AcademicEventResultKind = "regular"
	EventResultKindSOR     AcademicEventResultKind = "sor"
	EventResultKindSOCH    AcademicEventResultKind = "soch"
)

type AcademicAggregateResultKind string

const (
	AggregateResultKindTerm AcademicAggregateResultKind = "term"
	AggregateResultKindYear AcademicAggregateResultKind = "year"
)

func IsAllowedEventResultKindV2(kind string) bool {
	switch AcademicEventResultKind(kind) {
	case EventResultKindRegular, EventResultKindSOR, EventResultKindSOCH:
		return true
	default:
		return false
	}
}

func IsAllowedAggregateResultKindV2(kind string) bool {
	switch AcademicAggregateResultKind(kind) {
	case AggregateResultKindTerm, AggregateResultKindYear:
		return true
	default:
		return false
	}
}

// CanonicalIngestBundleV2 is an additive contract.
// Existing v1 ingest path remains untouched until explicit switch-over.
type CanonicalIngestBundleV2 struct {
	ContractVersion int                          `json:"contract_version"`
	Source          string                       `json:"source"`
	SourceAccount   string                       `json:"source_account"`
	IdempotencyKey  string                       `json:"idempotency_key"`
	SyncedAt        time.Time                    `json:"synced_at"`
	Identity        CanonicalProviderIdentityV2  `json:"identity"`
	Lessons         []CanonicalLessonV2          `json:"lessons"`
	Results         []CanonicalAcademicResultV2  `json:"results"`
	Aggregates      []CanonicalAcademicAggregate `json:"aggregates"`
	Attendance      []CanonicalAttendanceEventV2 `json:"attendance"`
	Evidence        []CanonicalResultEvidenceV2  `json:"evidence"`
	LocalAppProfile *CanonicalLocalAppProfileV2  `json:"local_app_profile,omitempty"`
}

type IngestResultV2 struct {
	BatchID          string `json:"batch_id"`
	AlreadyProcessed bool   `json:"already_processed"`
	MergedLessons    int    `json:"merged_lessons"`
	MergedResults    int    `json:"merged_results"`
	MergedAggregates int    `json:"merged_aggregates"`
	MergedAttendance int    `json:"merged_attendance"`
	InsertedEvidence int    `json:"inserted_evidence"`
}

type CanonicalProviderIdentityV2 struct {
	Provider             string `json:"provider"`
	ProviderAccountRef   string `json:"provider_account_ref"`
	ProviderPersonID     string `json:"provider_person_id"`
	ProviderSchoolID     string `json:"provider_school_id"`
	ProviderGroupID      string `json:"provider_group_id"`
	StudentFullName      string `json:"student_full_name"`
	SchoolName           string `json:"school_name"`
	ClassLabel           string `json:"class_label"`
	ClassTeacherFullName string `json:"class_teacher_full_name"`
}

type CanonicalLessonV2 struct {
	SourceLessonKey   string `json:"source_lesson_key"`
	ProviderLessonID  string `json:"provider_lesson_id"`
	ProviderSubjectID string `json:"provider_subject_id"`
	Date              string `json:"date"`
	LessonNumber      int    `json:"lesson_number"`
	SubjectName       string `json:"subject_name"`
	LessonPlace       string `json:"lesson_place"`
	StartTime         string `json:"start_time"`
	EndTime           string `json:"end_time"`
	Theme             string `json:"theme"`
	HomeworkText      string `json:"homework_text"`
	RequiresPhoto     bool   `json:"requires_photo"`
}

// Baseline kinds: regular, sor, soch.
type CanonicalAcademicResultV2 struct {
	SourceResultKey   string   `json:"source_result_key"`
	ResultKind        string   `json:"result_kind"`
	ProviderWorkID    string   `json:"provider_work_id"`
	ProviderMarkID    string   `json:"provider_mark_id"`
	ProviderSubjectID string   `json:"provider_subject_id"`
	SubjectName       string   `json:"subject_name"`
	LessonRefKey      string   `json:"lesson_ref_key"`
	RecordedOn        string   `json:"recorded_on"`
	PeriodID          string   `json:"period_id"`
	TermNo            *int     `json:"term_no,omitempty"`
	ValueText         string   `json:"value_text"`
	ValueNumeric      *float64 `json:"value_numeric,omitempty"`
	ResolvedMood      string   `json:"resolved_mood"`
}

// Baseline kinds: term, year.
type CanonicalAcademicAggregate struct {
	SourceAggregateKey string   `json:"source_aggregate_key"`
	ResultKind         string   `json:"result_kind"`
	ProviderSubjectID  string   `json:"provider_subject_id"`
	SubjectName        string   `json:"subject_name"`
	RecordedOn         string   `json:"recorded_on"`
	PeriodID           string   `json:"period_id"`
	TermNo             *int     `json:"term_no,omitempty"`
	YearLabel          string   `json:"year_label"`
	ValueText          string   `json:"value_text"`
	ValueNumeric       *float64 `json:"value_numeric,omitempty"`
	ResolvedMood       string   `json:"resolved_mood"`
}

type CanonicalAttendanceEventV2 struct {
	SourceEventKey    string `json:"source_event_key"`
	ProviderEventKey  string `json:"provider_event_key"`
	ProviderLessonRef string `json:"provider_lesson_ref"`
	ProviderSubjectID string `json:"provider_subject_id"`
	SubjectName       string `json:"subject_name"`
	LessonNumber      int    `json:"lesson_number"`
	RecordedOn        string `json:"recorded_on"`
	RawCode           string `json:"raw_code"`
	NormalizedStatus  string `json:"normalized_status"`
	Reason            string `json:"reason"`
}

type CanonicalResultEvidenceV2 struct {
	SourceResultRefKey    string `json:"source_result_ref_key"`
	SourceAggregateRefKey string `json:"source_aggregate_ref_key"`
	SourceEndpoint        string `json:"source_endpoint"`
	ProviderWorkID        string `json:"provider_work_id"`
	ProviderMarkID        string `json:"provider_mark_id"`
	ProviderPayloadPath   string `json:"provider_payload_path"`
	SourceMoodRaw         string `json:"source_mood_raw"`
	FingerprintSHA256     string `json:"fingerprint_sha256"`
}

type CanonicalLocalAppProfileV2 struct {
	Shift        *int   `json:"shift,omitempty"`
	ParentPhone1 string `json:"parent_phone_1"`
	ParentPhone2 string `json:"parent_phone_2"`
}
