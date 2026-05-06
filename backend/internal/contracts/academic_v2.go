package contracts

// Typed DTOs for v2 read surface.
// Additive only: v1 map-based endpoints remain untouched.

type ReadWindowV2DTO struct {
	Provider   string `json:"provider"`
	WindowFrom string `json:"window_from"`
	WindowTo   string `json:"window_to"`
	SnapshotAt string `json:"snapshot_at"`
	WindowKey  string `json:"window_key"`
}

type ProviderIdentityV2DTO struct {
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

// Backward-compat alias for transitional tests.
type AcademicIdentityV2DTO = ProviderIdentityV2DTO

type ProfileV2DTO struct {
	Window           ReadWindowV2DTO       `json:"window"`
	ProviderIdentity ProviderIdentityV2DTO `json:"provider_identity"`
	LocalAppProfile  *LocalAppProfileV2DTO `json:"local_app_profile,omitempty"`
}

type AcademicLessonV2DTO struct {
	LessonID          string `json:"lesson_id"`
	Provider          string `json:"provider"`
	ProviderLessonID  string `json:"provider_lesson_id"`
	ProviderSubjectID string `json:"provider_subject_id"`
	LessonDate        string `json:"lesson_date"`
	LessonNumber      int    `json:"lesson_number"`
	SubjectName       string `json:"subject_name"`
	LessonPlace       string `json:"lesson_place"`
	StartTime         string `json:"start_time"`
	EndTime           string `json:"end_time"`
	Theme             string `json:"theme"`
	HomeworkText      string `json:"homework_text"`
	HomeworkStatus    string `json:"homework_status"`
}

type AcademicResultV2DTO struct {
	ResultID          string `json:"result_id"`
	Provider          string `json:"provider"`
	ResultKind        string `json:"result_kind"`
	ProviderWorkID    string `json:"provider_work_id"`
	ProviderMarkID    string `json:"provider_mark_id"`
	ProviderSubjectID string `json:"provider_subject_id"`
	SubjectName       string `json:"subject_name"`
	ValueText         string `json:"value_text"`
	ResolvedMood      string `json:"resolved_mood"`
	RecordedOn        string `json:"recorded_on"`
	SourceEndpoint    string `json:"source_endpoint"`
	SourceMoodRaw     string `json:"source_mood_raw"`
}

type AcademicAggregateV2DTO struct {
	AggregateID       string `json:"aggregate_id"`
	Provider          string `json:"provider"`
	ResultKind        string `json:"result_kind"`
	ProviderSubjectID string `json:"provider_subject_id"`
	SubjectName       string `json:"subject_name"`
	ValueText         string `json:"value_text"`
	ResolvedMood      string `json:"resolved_mood"`
	RecordedOn        string `json:"recorded_on"`
	TermNo            *int   `json:"term_no,omitempty"`
	YearLabel         string `json:"year_label"`
}

type AcademicAttendanceV2DTO struct {
	AttendanceID      string `json:"attendance_id"`
	Provider          string `json:"provider"`
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

type AcademicOverviewCountsV2DTO struct {
	LessonsInWindow    int `json:"lessons_in_window"`
	ResultsInWindow    int `json:"results_in_window"`
	AggregatesInWindow int `json:"aggregates_in_window"`
	AttendanceAlerts   int `json:"attendance_alerts"`
}

type ResultHighlightV2DTO struct {
	ResultID     string `json:"result_id"`
	ResultKind   string `json:"result_kind"`
	SubjectName  string `json:"subject_name"`
	ValueText    string `json:"value_text"`
	RecordedOn   string `json:"recorded_on"`
	ResolvedMood string `json:"resolved_mood"`
}

type LessonHighlightV2DTO struct {
	LessonID     string `json:"lesson_id"`
	LessonDate   string `json:"lesson_date"`
	LessonNumber int    `json:"lesson_number"`
	SubjectName  string `json:"subject_name"`
	Theme        string `json:"theme"`
	HomeworkText string `json:"homework_text"`
}

type AcademicOverviewHighlightsV2DTO struct {
	RecentResults   []ResultHighlightV2DTO `json:"recent_results"`
	UpcomingLessons []LessonHighlightV2DTO `json:"upcoming_lessons"`
}

type LocalAppProfileV2DTO struct {
	Shift        *int   `json:"shift,omitempty"`
	ParentPhone1 string `json:"parent_phone_1"`
	ParentPhone2 string `json:"parent_phone_2"`
}

type AcademicOverviewV2DTO struct {
	Window           ReadWindowV2DTO                 `json:"window"`
	ProviderIdentity ProviderIdentityV2DTO           `json:"provider_identity"`
	LocalAppProfile  *LocalAppProfileV2DTO           `json:"local_app_profile,omitempty"`
	Counts           AcademicOverviewCountsV2DTO     `json:"counts"`
	Highlights       AcademicOverviewHighlightsV2DTO `json:"highlights"`

	// Transitional compatibility fields.
	Identity   ProviderIdentityV2DTO     `json:"identity,omitempty"`
	Lessons    []AcademicLessonV2DTO     `json:"lessons,omitempty"`
	Results    []AcademicResultV2DTO     `json:"results,omitempty"`
	Aggregates []AcademicAggregateV2DTO  `json:"aggregates,omitempty"`
	Attendance []AcademicAttendanceV2DTO `json:"attendance,omitempty"`
}

type AcademicResultsResponseV2DTO struct {
	Window     ReadWindowV2DTO           `json:"window"`
	Lessons    []AcademicLessonV2DTO     `json:"lessons"`
	Results    []AcademicResultV2DTO     `json:"results"`
	Aggregates []AcademicAggregateV2DTO  `json:"aggregates"`
	Attendance []AcademicAttendanceV2DTO `json:"attendance"`
}
