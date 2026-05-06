package jobhandlers

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/jobs"
)

type Enqueuer interface {
	Enqueue(ctx context.Context, req jobs.EnqueueRequest) (string, bool, error)
}

type Analytics interface {
	RecomputeDailyStats(ctx context.Context, studentID uuid.UUID, statsDate time.Time) error
	RecomputeWeeklyStats(ctx context.Context, studentID uuid.UUID, weekStart, weekEnd time.Time) error
	DetectStaleData(ctx context.Context, studentID uuid.UUID, now time.Time, maxAge time.Duration) error
}

type DigestBuilder interface {
	BuildHomeworkDigest(ctx context.Context, studentID uuid.UUID, forDate time.Time, mode string) (string, error)
}

type JobsWorker struct {
	jobs      Enqueuer
	analytics Analytics
	digest    DigestBuilder
}

func NewJobsWorker(jobsSvc Enqueuer, analyticsSvc Analytics, digestBuilder DigestBuilder) *JobsWorker {
	return &JobsWorker{
		jobs:      jobsSvc,
		analytics: analyticsSvc,
		digest:    digestBuilder,
	}
}

func (w *JobsWorker) Handlers() map[jobs.JobType]jobs.Handler {
	return map[jobs.JobType]jobs.Handler{
		jobs.JobIngestPostProcessing: w.IngestPostProcessing,
		jobs.JobRecomputeDailyStats:  w.RecomputeDailyStats,
		jobs.JobRecomputeWeeklyStats: w.RecomputeWeeklyStats,
		jobs.JobGenerateParentDigest: w.GenerateParentDigest,
		jobs.JobStaleDataDetection:   w.DetectStaleData,
	}
}

func (w *JobsWorker) IngestPostProcessing(ctx context.Context, job jobs.Job) error {
	studentID, err := parseStudentID(job.Payload)
	if err != nil {
		return err
	}
	date, err := parseDate(job.Payload, "date", false, time.Now().UTC())
	if err != nil {
		return err
	}
	weekStart, weekEnd := weekBounds(date)

	toEnqueue := []jobs.EnqueueRequest{
		{
			Type:           jobs.JobRecomputeDailyStats,
			IdempotencyKey: fmt.Sprintf("daily:%s:%s", studentID.String(), date.Format("2006-01-02")),
			Priority:       40,
			Payload: map[string]any{
				"student_id": studentID.String(),
				"date":       date.Format("2006-01-02"),
			},
		},
		{
			Type:           jobs.JobRecomputeWeeklyStats,
			IdempotencyKey: fmt.Sprintf("weekly:%s:%s", studentID.String(), weekStart.Format("2006-01-02")),
			Priority:       45,
			Payload: map[string]any{
				"student_id":  studentID.String(),
				"week_start":  weekStart.Format("2006-01-02"),
				"week_end":    weekEnd.Format("2006-01-02"),
				"source_date": date.Format("2006-01-02"),
			},
		},
		{
			Type:           jobs.JobGenerateParentDigest,
			IdempotencyKey: fmt.Sprintf("parentdigest:%s:%s", studentID.String(), date.Format("2006-01-02")),
			Priority:       30,
			Payload: map[string]any{
				"student_id": studentID.String(),
				"date":       date.Format("2006-01-02"),
			},
		},
		{
			Type:           jobs.JobStaleDataDetection,
			IdempotencyKey: fmt.Sprintf("stale:%s:%s", studentID.String(), date.Format("2006-01-02")),
			Priority:       60,
			Payload: map[string]any{
				"student_id":    studentID.String(),
				"max_age_hours": 72,
			},
		},
	}

	for _, req := range toEnqueue {
		if _, _, err := w.jobs.Enqueue(ctx, req); err != nil {
			return fmt.Errorf("enqueue follow-up job %s: %w", req.Type, err)
		}
	}
	return nil
}

func (w *JobsWorker) RecomputeDailyStats(ctx context.Context, job jobs.Job) error {
	studentID, err := parseStudentID(job.Payload)
	if err != nil {
		return err
	}
	date, err := parseDate(job.Payload, "date", true, time.Time{})
	if err != nil {
		return err
	}
	return w.analytics.RecomputeDailyStats(ctx, studentID, date)
}

func (w *JobsWorker) RecomputeWeeklyStats(ctx context.Context, job jobs.Job) error {
	studentID, err := parseStudentID(job.Payload)
	if err != nil {
		return err
	}

	weekStart, err := parseDate(job.Payload, "week_start", false, time.Time{})
	if err != nil {
		return err
	}
	weekEnd, err := parseDate(job.Payload, "week_end", false, time.Time{})
	if err != nil {
		return err
	}
	if weekStart.IsZero() || weekEnd.IsZero() || weekEnd.Before(weekStart) {
		sourceDate, sourceErr := parseDate(job.Payload, "source_date", true, time.Time{})
		if sourceErr != nil {
			return sourceErr
		}
		weekStart, weekEnd = weekBounds(sourceDate)
	}

	return w.analytics.RecomputeWeeklyStats(ctx, studentID, weekStart, weekEnd)
}

func (w *JobsWorker) GenerateParentDigest(ctx context.Context, job jobs.Job) error {
	studentID, err := parseStudentID(job.Payload)
	if err != nil {
		return err
	}
	date, err := parseDate(job.Payload, "date", false, time.Now().UTC())
	if err != nil {
		return err
	}
	mode := strings.ToLower(strings.TrimSpace(readPayloadString(job.Payload, "mode")))
	if mode != "topic" {
		mode = "homework"
	}

	digest, err := w.digest.BuildHomeworkDigest(ctx, studentID, date, mode)
	if err != nil {
		return fmt.Errorf("build parent digest: %w", err)
	}

	dispatchKey := fmt.Sprintf("dispatch:%s:%s:%s", studentID.String(), date.Format("2006-01-02"), mode)
	_, _, err = w.jobs.Enqueue(ctx, jobs.EnqueueRequest{
		Type:           jobs.JobDispatchWhatsApp,
		IdempotencyKey: dispatchKey,
		Priority:       20,
		Payload: map[string]any{
			"kind":       "homework_digest",
			"student_id": studentID.String(),
			"date":       date.Format("2006-01-02"),
			"mode":       mode,
			"message":    digest,
		},
	})
	if err != nil {
		return fmt.Errorf("enqueue dispatch_whatsapp: %w", err)
	}
	return nil
}

func (w *JobsWorker) DetectStaleData(ctx context.Context, job jobs.Job) error {
	studentID, err := parseStudentID(job.Payload)
	if err != nil {
		return err
	}
	maxAge, err := parseHours(job.Payload, "max_age_hours", 72)
	if err != nil {
		return err
	}
	return w.analytics.DetectStaleData(ctx, studentID, time.Now().UTC(), maxAge)
}

func parseStudentID(payload map[string]any) (uuid.UUID, error) {
	raw := readPayloadString(payload, "student_id")
	if raw == "" {
		return uuid.Nil, jobs.Permanent(fmt.Errorf("student_id is required"))
	}
	parsed, err := uuid.Parse(raw)
	if err != nil {
		return uuid.Nil, jobs.Permanent(fmt.Errorf("invalid student_id: %w", err))
	}
	return parsed, nil
}

func parseDate(payload map[string]any, key string, required bool, fallback time.Time) (time.Time, error) {
	raw := readPayloadString(payload, key)
	if raw == "" {
		if required {
			return time.Time{}, jobs.Permanent(fmt.Errorf("%s is required", key))
		}
		if fallback.IsZero() {
			return time.Time{}, nil
		}
		return fallback.UTC(), nil
	}
	parsed, err := time.Parse("2006-01-02", raw)
	if err != nil {
		return time.Time{}, jobs.Permanent(fmt.Errorf("%s must match YYYY-MM-DD", key))
	}
	return parsed.UTC(), nil
}

func parseHours(payload map[string]any, key string, fallback int) (time.Duration, error) {
	raw := readPayloadString(payload, key)
	if raw == "" {
		return time.Duration(fallback) * time.Hour, nil
	}
	var hours int
	_, err := fmt.Sscanf(raw, "%d", &hours)
	if err != nil || hours <= 0 {
		return 0, jobs.Permanent(fmt.Errorf("%s must be a positive integer", key))
	}
	return time.Duration(hours) * time.Hour, nil
}

func weekBounds(base time.Time) (time.Time, time.Time) {
	base = base.UTC()
	weekday := int(base.Weekday())
	if weekday == 0 {
		weekday = 7
	}
	start := time.Date(base.Year(), base.Month(), base.Day(), 0, 0, 0, 0, time.UTC).AddDate(0, 0, -(weekday - 1))
	end := start.AddDate(0, 0, 6)
	return start, end
}

func readPayloadString(payload map[string]any, key string) string {
	if payload == nil {
		return ""
	}
	value, ok := payload[key]
	if !ok || value == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprintf("%v", value))
}
