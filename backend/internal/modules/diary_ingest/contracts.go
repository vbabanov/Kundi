package diary_ingest

import "time"

type CanonicalIngestBundle struct {
	Source         string            `json:"source"`
	SourceAccount  string            `json:"source_account"`
	IdempotencyKey string            `json:"idempotency_key"`
	SyncedAt       time.Time         `json:"synced_at"`
	SourceIDs      map[string]string `json:"source_ids"`
	Profile        CanonicalProfile  `json:"profile"`
	Lessons        []CanonicalLesson `json:"lessons"`
	Attendance     []AttendanceEvent `json:"attendance"`
}

type CanonicalProfile struct {
	FirstName  string `json:"first_name"`
	LastName   string `json:"last_name"`
	GradeLevel int    `json:"grade_level"`
	ClassLabel string `json:"class_label"`
	SchoolName string `json:"school_name"`
}

type CanonicalLesson struct {
	SourceLessonKey string          `json:"source_lesson_key"`
	Date            string          `json:"date"`
	LessonNumber    int             `json:"lesson_number"`
	SubjectName     string          `json:"subject_name"`
	LessonPlace     string          `json:"lesson_place"`
	StartTime       string          `json:"start_time"`
	EndTime         string          `json:"end_time"`
	TopicTitle      string          `json:"topic_title"`
	Homework        HomeworkPayload `json:"homework"`
	Grades          []GradePayload  `json:"grades"`
}

type HomeworkPayload struct {
	SourceHomeworkKey string `json:"source_homework_key"`
	Description       string `json:"description"`
	RequiresPhoto     bool   `json:"requires_photo"`
}

type GradePayload struct {
	SourceGradeKey string `json:"source_grade_key"`
	Value          string `json:"value"`
	Mood           string `json:"mood"`
	Type           string `json:"type"`
	IsAbsent       bool   `json:"is_absent"`
}

type AttendanceEvent struct {
	SourceEventKey string `json:"source_event_key"`
	Date           string `json:"date"`
	Code           string `json:"code"`
	Reason         string `json:"reason"`
}

type IngestResult struct {
	BatchID          string `json:"batch_id"`
	AlreadyProcessed bool   `json:"already_processed"`
	MergedLessons    int    `json:"merged_lessons"`
	MergedGrades     int    `json:"merged_grades"`
}
