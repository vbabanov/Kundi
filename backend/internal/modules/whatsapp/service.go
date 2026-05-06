package whatsapp

import (
	"context"
	"strings"
	"time"

	"github.com/kundi/kundi/backend/internal/modules/jobs"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
	"github.com/kundi/kundi/backend/internal/platform/validate"
)

type Service struct {
	jobs *jobs.Service
}

func NewService(jobsService *jobs.Service) *Service {
	return &Service{jobs: jobsService}
}

func (s *Service) SendHomeworkDigest(
	ctx context.Context,
	studentID string,
	date string,
	mode string,
	idempotencyKey string,
) (string, bool, error) {
	return s.SendHomeworkDigestWithMessage(ctx, studentID, date, mode, "", idempotencyKey, nil)
}

func (s *Service) SendHomeworkDigestWithMessage(
	ctx context.Context,
	studentID string,
	date string,
	mode string,
	message string,
	idempotencyKey string,
	parentPhones []string,
) (string, bool, error) {
	if strings.TrimSpace(studentID) == "" {
		return "", false, apperrors.BadRequest("student_required", "student id is required")
	}
	if !validate.IdempotencyKey(idempotencyKey) {
		return "", false, apperrors.BadRequest("idempotency_invalid", "idempotency key is invalid")
	}
	if strings.TrimSpace(date) == "" {
		date = time.Now().UTC().Format("2006-01-02")
	}
	mode = strings.ToLower(strings.TrimSpace(mode))
	if mode != "topic" {
		mode = "homework"
	}
	normalizedPhones := make([]string, 0, len(parentPhones))
	for _, phone := range parentPhones {
		trimmed := strings.TrimSpace(phone)
		if trimmed != "" {
			normalizedPhones = append(normalizedPhones, trimmed)
		}
	}

	return s.jobs.Enqueue(ctx, jobs.EnqueueRequest{
		Type:           jobs.JobDispatchWhatsApp,
		IdempotencyKey: idempotencyKey,
		Priority:       30,
		Payload: map[string]any{
			"kind":          "homework_digest",
			"student_id":    studentID,
			"date":          date,
			"mode":          mode,
			"message":       strings.TrimSpace(message),
			"parent_phones": normalizedPhones,
		},
	})
}

func (s *Service) SendHomeworkPhoto(
	ctx context.Context,
	studentID,
	homeworkID,
	fileName,
	objectKey,
	caption,
	idempotencyKey string,
	parentPhones []string,
) (string, bool, error) {
	if strings.TrimSpace(homeworkID) == "" {
		return "", false, apperrors.BadRequest("homework_required", "homework id is required")
	}
	if !validate.IdempotencyKey(idempotencyKey) {
		return "", false, apperrors.BadRequest("idempotency_invalid", "idempotency key is invalid")
	}
	if strings.TrimSpace(objectKey) == "" {
		objectKey = "homework-photo://" + studentID + "/" + fileName
	}
	normalizedPhones := make([]string, 0, len(parentPhones))
	for _, phone := range parentPhones {
		trimmed := strings.TrimSpace(phone)
		if trimmed != "" {
			normalizedPhones = append(normalizedPhones, trimmed)
		}
	}
	return s.jobs.Enqueue(ctx, jobs.EnqueueRequest{
		Type:           jobs.JobDispatchWhatsApp,
		IdempotencyKey: idempotencyKey,
		Priority:       20,
		Payload: map[string]any{
			"kind":          "homework_photo",
			"student_id":    studentID,
			"homework_id":   homeworkID,
			"file_name":     fileName,
			"object_key":    objectKey,
			"message":       strings.TrimSpace(caption),
			"caption":       strings.TrimSpace(caption),
			"parent_phones": normalizedPhones,
		},
	})
}
