package diary_ingest

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
	"github.com/kundi/kundi/backend/internal/platform/observability"
	"github.com/kundi/kundi/backend/internal/platform/validate"
)

type Repository interface {
	CreateBatch(ctx context.Context, studentID uuid.UUID, bundle CanonicalIngestBundle, checksum string) (batchID uuid.UUID, inserted bool, err error)
	MergeBundle(ctx context.Context, studentID uuid.UUID, bundle CanonicalIngestBundle) (mergedLessons int, mergedGrades int, err error)
	MarkMerged(ctx context.Context, batchID uuid.UUID) error
}

type Service struct {
	repo    Repository
	metrics observability.Metrics
	tracer  observability.Tracer
}

func NewService(repo Repository, hooks ...observability.Hooks) *Service {
	observe := observability.Ensure(observability.Hooks{})
	if len(hooks) > 0 {
		observe = observability.Ensure(hooks[0])
	}
	return &Service{
		repo:    repo,
		metrics: observe.Metrics,
		tracer:  observe.Tracer,
	}
}

func (s *Service) IngestBundle(ctx context.Context, studentID uuid.UUID, bundle CanonicalIngestBundle) (result IngestResult, retErr error) {
	startedAt := time.Now()
	baseTags := map[string]string{
		"path":  "ingest_v1",
		"stage": "legacy",
	}
	s.metrics.Incr("backend.ingest.requests_total", baseTags)
	ctx, finish := s.tracer.Start(ctx, "ingest.bundle.v1")
	defer func() {
		outcome := "success"
		errorClass := "none"
		if retErr != nil {
			outcome = "failure"
			errorClass = classifyErrorClass(retErr)
			s.metrics.Incr("backend.ingest.failure_total", mergeTags(baseTags, map[string]string{
				"error_class": errorClass,
			}))
		} else {
			s.metrics.Incr("backend.ingest.success_total", baseTags)
			s.metrics.Observe("backend.ingest.merge_lessons", float64(result.MergedLessons), baseTags)
			s.metrics.Observe("backend.ingest.merge_grades", float64(result.MergedGrades), baseTags)
		}
		s.metrics.Observe("backend.ingest.latency_ms", float64(time.Since(startedAt).Milliseconds()), mergeTags(baseTags, map[string]string{
			"outcome":     outcome,
			"error_class": errorClass,
		}))
		finish(retErr)
	}()

	normalized := normalizeBundle(bundle)
	if err := validateBundle(normalized); err != nil {
		retErr = err
		return IngestResult{}, retErr
	}
	checksum, err := checksumBundle(normalized)
	if err != nil {
		retErr = apperrors.Internal("bundle_checksum_failed", "failed to compute bundle checksum", err)
		return IngestResult{}, retErr
	}

	batchID, inserted, err := s.repo.CreateBatch(ctx, studentID, normalized, checksum)
	if err != nil {
		if errors.Is(err, ErrIdempotencyConflict) {
			retErr = apperrors.Conflict("ingest_idempotency_conflict", "idempotency key already used for another payload")
			return IngestResult{}, retErr
		}
		retErr = apperrors.Internal("ingest_batch_failed", "failed to create ingest batch", err)
		return IngestResult{}, retErr
	}
	if !inserted {
		result = IngestResult{BatchID: batchID.String(), AlreadyProcessed: true}
		return result, nil
	}

	mergedLessons, mergedGrades, err := s.repo.MergeBundle(ctx, studentID, normalized)
	if err != nil {
		retErr = apperrors.Internal("ingest_merge_failed", "failed to merge ingest bundle", err)
		return IngestResult{}, retErr
	}
	if err := s.repo.MarkMerged(ctx, batchID); err != nil {
		retErr = apperrors.Internal("ingest_finalize_failed", "failed to finalize ingest batch", err)
		return IngestResult{}, retErr
	}
	result = IngestResult{
		BatchID:          batchID.String(),
		AlreadyProcessed: false,
		MergedLessons:    mergedLessons,
		MergedGrades:     mergedGrades,
	}
	return result, nil
}

func mergeTags(base map[string]string, extra map[string]string) map[string]string {
	out := make(map[string]string, len(base)+len(extra))
	for key, value := range base {
		out[key] = value
	}
	for key, value := range extra {
		out[key] = value
	}
	return out
}

func classifyErrorClass(err error) string {
	var appErr *apperrors.Error
	if !errors.As(err, &appErr) {
		return "internal"
	}
	switch appErr.StatusCode {
	case http.StatusBadRequest:
		return "bad_request"
	case http.StatusUnauthorized:
		return "unauthorized"
	case http.StatusForbidden:
		return "forbidden"
	case http.StatusNotFound:
		return "not_found"
	case http.StatusConflict:
		return "conflict"
	default:
		return "internal"
	}
}

func validateBundle(bundle CanonicalIngestBundle) error {
	if !validate.Source(bundle.Source) {
		return apperrors.BadRequest("invalid_source", "bundle source is not supported")
	}
	if !validate.IdempotencyKey(bundle.IdempotencyKey) {
		return apperrors.BadRequest("invalid_idempotency_key", "idempotency key has invalid format")
	}
	if len(bundle.Lessons) == 0 && len(bundle.Attendance) == 0 {
		return apperrors.BadRequest("empty_bundle", "ingest bundle has no lessons or attendance")
	}

	seenLessonKeys := make(map[string]struct{}, len(bundle.Lessons))
	for _, lesson := range bundle.Lessons {
		if strings.TrimSpace(lesson.SourceLessonKey) == "" {
			return apperrors.BadRequest("invalid_lesson_key", "source lesson key must not be empty after normalization")
		}
		if _, exists := seenLessonKeys[lesson.SourceLessonKey]; exists {
			return apperrors.BadRequest("duplicate_lesson_key", "bundle contains duplicated lesson keys")
		}
		seenLessonKeys[lesson.SourceLessonKey] = struct{}{}

		if _, err := time.Parse("2006-01-02", lesson.Date); err != nil {
			return apperrors.BadRequest("invalid_lesson_date", "lesson date must match YYYY-MM-DD")
		}
		if lesson.LessonNumber < 0 {
			return apperrors.BadRequest("invalid_lesson_number", "lesson number must be non-negative")
		}
		if lesson.StartTime != "" {
			if _, err := time.Parse("15:04", lesson.StartTime); err != nil {
				return apperrors.BadRequest("invalid_start_time", "lesson start_time must match HH:MM")
			}
		}
		if lesson.EndTime != "" {
			if _, err := time.Parse("15:04", lesson.EndTime); err != nil {
				return apperrors.BadRequest("invalid_end_time", "lesson end_time must match HH:MM")
			}
		}
	}

	for _, event := range bundle.Attendance {
		if _, err := time.Parse("2006-01-02", event.Date); err != nil {
			return apperrors.BadRequest("invalid_attendance_date", "attendance date must match YYYY-MM-DD")
		}
		switch event.Code {
		case "present", "absent", "late", "excused":
		default:
			return apperrors.BadRequest("invalid_attendance_code", "attendance code must be present|absent|late|excused")
		}
	}
	return nil
}

func checksumBundle(bundle CanonicalIngestBundle) (string, error) {
	payload, err := json.Marshal(bundle)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(payload)
	return hex.EncodeToString(sum[:]), nil
}

func normalizeBundle(bundle CanonicalIngestBundle) CanonicalIngestBundle {
	bundle.Source = strings.ToLower(strings.TrimSpace(bundle.Source))
	bundle.SourceAccount = strings.TrimSpace(bundle.SourceAccount)
	bundle.IdempotencyKey = strings.TrimSpace(bundle.IdempotencyKey)
	if !bundle.SyncedAt.IsZero() {
		bundle.SyncedAt = bundle.SyncedAt.UTC()
	}

	if len(bundle.SourceIDs) > 0 {
		normalizedIDs := make(map[string]string, len(bundle.SourceIDs))
		for key, value := range bundle.SourceIDs {
			trimmedKey := strings.TrimSpace(key)
			trimmedValue := strings.TrimSpace(value)
			if trimmedKey == "" || trimmedValue == "" {
				continue
			}
			normalizedIDs[strings.ToLower(trimmedKey)] = trimmedValue
		}
		bundle.SourceIDs = normalizedIDs
	}

	for i := range bundle.Lessons {
		lesson := &bundle.Lessons[i]
		lesson.SourceLessonKey = strings.TrimSpace(lesson.SourceLessonKey)
		if lesson.SourceLessonKey == "" {
			lesson.SourceLessonKey = defaultLessonKey(*lesson)
		}
		lesson.SubjectName = strings.TrimSpace(lesson.SubjectName)
		lesson.LessonPlace = strings.TrimSpace(lesson.LessonPlace)
		lesson.TopicTitle = strings.TrimSpace(lesson.TopicTitle)
		lesson.Homework.Description = strings.TrimSpace(lesson.Homework.Description)
		lesson.StartTime = strings.TrimSpace(lesson.StartTime)
		lesson.EndTime = strings.TrimSpace(lesson.EndTime)

		for j := range lesson.Grades {
			grade := &lesson.Grades[j]
			grade.SourceGradeKey = strings.TrimSpace(grade.SourceGradeKey)
			grade.Value = strings.TrimSpace(grade.Value)
			grade.Mood = strings.TrimSpace(grade.Mood)
			grade.Type = normalizeGradeType(grade.Type)
		}
		lesson.Grades = deduplicateGrades(lesson.Grades)
	}
	bundle.Lessons = deduplicateLessons(bundle.Lessons)
	sortLessons(bundle.Lessons)

	for i := range bundle.Attendance {
		event := &bundle.Attendance[i]
		event.SourceEventKey = strings.TrimSpace(event.SourceEventKey)
		event.Date = strings.TrimSpace(event.Date)
		event.Code = strings.ToLower(strings.TrimSpace(event.Code))
		event.Reason = strings.TrimSpace(event.Reason)
	}
	bundle.Attendance = deduplicateAttendance(bundle.Attendance)
	sortAttendance(bundle.Attendance)
	return bundle
}

func normalizeGradeType(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "regular", "absence", "behavior":
		return strings.ToLower(strings.TrimSpace(raw))
	default:
		return "regular"
	}
}

func defaultLessonKey(lesson CanonicalLesson) string {
	base := fmt.Sprintf("%s:%d:%s", lesson.Date, lesson.LessonNumber, strings.ToLower(strings.TrimSpace(lesson.SubjectName)))
	sum := sha256.Sum256([]byte(base))
	return hex.EncodeToString(sum[:])
}

func deduplicateLessons(items []CanonicalLesson) []CanonicalLesson {
	if len(items) <= 1 {
		return items
	}
	byKey := make(map[string]CanonicalLesson, len(items))
	order := make([]string, 0, len(items))
	for _, lesson := range items {
		key := strings.TrimSpace(lesson.SourceLessonKey)
		existing, exists := byKey[key]
		if !exists {
			byKey[key] = lesson
			order = append(order, key)
			continue
		}
		byKey[key] = mergeLessons(existing, lesson)
	}

	out := make([]CanonicalLesson, 0, len(order))
	for _, key := range order {
		out = append(out, byKey[key])
	}
	return out
}

func mergeLessons(base CanonicalLesson, incoming CanonicalLesson) CanonicalLesson {
	if incoming.Date != "" {
		base.Date = incoming.Date
	}
	if incoming.LessonNumber >= 0 {
		base.LessonNumber = incoming.LessonNumber
	}
	if incoming.LessonPlace != "" {
		base.LessonPlace = incoming.LessonPlace
	}
	if incoming.SubjectName != "" {
		base.SubjectName = incoming.SubjectName
	}
	if incoming.StartTime != "" {
		base.StartTime = incoming.StartTime
	}
	if incoming.EndTime != "" {
		base.EndTime = incoming.EndTime
	}
	if incoming.TopicTitle != "" {
		base.TopicTitle = incoming.TopicTitle
	}
	if strings.TrimSpace(incoming.Homework.Description) != "" || incoming.Homework.RequiresPhoto || incoming.Homework.SourceHomeworkKey != "" {
		base.Homework = incoming.Homework
	}
	if len(incoming.Grades) > 0 {
		base.Grades = deduplicateGrades(append(base.Grades, incoming.Grades...))
	}
	return base
}

func deduplicateGrades(items []GradePayload) []GradePayload {
	if len(items) <= 1 {
		return items
	}
	byKey := make(map[string]GradePayload, len(items))
	order := make([]string, 0, len(items))
	for index, grade := range items {
		if strings.TrimSpace(grade.Value) == "" {
			continue
		}
		key := strings.TrimSpace(grade.SourceGradeKey)
		if key == "" {
			key = fmt.Sprintf("index:%d:%s:%s", index, strings.ToLower(strings.TrimSpace(grade.Type)), strings.TrimSpace(grade.Value))
		}
		if _, exists := byKey[key]; !exists {
			order = append(order, key)
		}
		byKey[key] = grade
	}
	out := make([]GradePayload, 0, len(order))
	for _, key := range order {
		out = append(out, byKey[key])
	}
	return out
}

func deduplicateAttendance(items []AttendanceEvent) []AttendanceEvent {
	if len(items) <= 1 {
		return items
	}
	byKey := make(map[string]AttendanceEvent, len(items))
	order := make([]string, 0, len(items))
	for _, event := range items {
		key := strings.TrimSpace(event.SourceEventKey)
		if key == "" {
			key = fmt.Sprintf("%s|%s|%s", event.Date, strings.ToLower(event.Code), strings.ToLower(strings.TrimSpace(event.Reason)))
		}
		if _, exists := byKey[key]; !exists {
			order = append(order, key)
		}
		byKey[key] = event
	}
	out := make([]AttendanceEvent, 0, len(order))
	for _, key := range order {
		out = append(out, byKey[key])
	}
	return out
}

func sortLessons(items []CanonicalLesson) {
	sort.SliceStable(items, func(i, j int) bool {
		left := items[i]
		right := items[j]
		if left.Date != right.Date {
			return left.Date < right.Date
		}
		if left.LessonNumber != right.LessonNumber {
			return left.LessonNumber < right.LessonNumber
		}
		return left.SourceLessonKey < right.SourceLessonKey
	})
}

func sortAttendance(items []AttendanceEvent) {
	sort.SliceStable(items, func(i, j int) bool {
		left := items[i]
		right := items[j]
		if left.Date != right.Date {
			return left.Date < right.Date
		}
		if left.Code != right.Code {
			return left.Code < right.Code
		}
		return left.SourceEventKey < right.SourceEventKey
	})
}
