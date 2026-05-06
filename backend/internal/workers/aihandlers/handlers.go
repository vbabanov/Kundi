package aihandlers

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	assistantmodule "github.com/kundi/kundi/backend/internal/modules/assistant"
	"github.com/kundi/kundi/backend/internal/modules/jobs"
)

type Assistant interface {
	Message(ctx context.Context, cmd assistantmodule.MessageCommand) (assistantmodule.Response, error)
}

type Audit interface {
	Log(ctx context.Context, action string, entityType string, entityID string, studentID string, metadata map[string]any) error
}

type Worker struct {
	assistant Assistant
	audit     Audit
}

func NewWorker(assistant Assistant, audit Audit) *Worker {
	return &Worker{
		assistant: assistant,
		audit:     audit,
	}
}

func (w *Worker) Handlers() map[jobs.JobType]jobs.Handler {
	return map[jobs.JobType]jobs.Handler{
		jobs.JobAIPostProcessing: w.AIPostProcessing,
	}
}

func (w *Worker) AIPostProcessing(ctx context.Context, job jobs.Job) error {
	studentID := strings.TrimSpace(fmt.Sprintf("%v", job.Payload["student_id"]))
	if studentID == "" {
		return fmt.Errorf("student_id is required")
	}
	text := strings.TrimSpace(fmt.Sprintf("%v", job.Payload["text"]))
	if text == "" {
		return fmt.Errorf("text is required")
	}
	mode := strings.TrimSpace(fmt.Sprintf("%v", job.Payload["mode"]))
	if mode == "" {
		mode = string(assistantmodule.ModeTutor)
	}

	gradeLevel := parseInt(job.Payload["grade_level"], 7)
	response, err := w.assistant.Message(ctx, assistantmodule.MessageCommand{
		StudentID:  studentID,
		Mode:       assistantmodule.Mode(mode),
		GradeLevel: gradeLevel,
		Text:       text,
	})
	if err != nil {
		return err
	}

	if w.audit != nil {
		_ = w.audit.Log(ctx, "ai_post_processing", "jobs", job.ID, studentID, map[string]any{
			"mode":         mode,
			"grade_level":  gradeLevel,
			"text_len":     len(text),
			"response_len": len(response.Text),
		})
	}
	return nil
}

func parseInt(raw any, fallback int) int {
	if raw == nil {
		return fallback
	}
	switch value := raw.(type) {
	case int:
		return value
	case int64:
		return int(value)
	case float64:
		return int(value)
	case string:
		parsed, err := strconv.Atoi(strings.TrimSpace(value))
		if err != nil {
			return fallback
		}
		return parsed
	default:
		return fallback
	}
}
