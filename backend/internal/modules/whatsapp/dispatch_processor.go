package whatsapp

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/jobs"
)

type DispatchProcessor struct {
	store    DispatchStore
	provider Provider
}

func NewDispatchProcessor(store DispatchStore, provider Provider) *DispatchProcessor {
	return &DispatchProcessor{
		store:    store,
		provider: provider,
	}
}

func (p *DispatchProcessor) HandleJob(ctx context.Context, job jobs.Job) error {
	studentIDRaw := readString(job.Payload, "student_id")
	studentID, err := uuid.Parse(studentIDRaw)
	if err != nil {
		return jobs.Permanent(fmt.Errorf("dispatch job student_id invalid: %w", err))
	}

	kind := normalizeDispatchType(readString(job.Payload, "kind"))
	dispatchRecord, _, err := p.store.UpsertPending(
		ctx,
		studentID,
		kind,
		job.Payload,
		job.IdempotencyKey,
	)
	if err != nil {
		return fmt.Errorf("upsert dispatch pending: %w", err)
	}
	if dispatchRecord.Status == "sent" {
		return nil
	}

	message := readString(job.Payload, "message")
	if message == "" && kind == "homework_digest" {
		date := readString(job.Payload, "date")
		if date == "" {
			date = "today"
		}
		message = "Homework digest for " + date
	}
	objectKey := readString(job.Payload, "object_key")
	if err := validateDispatchPayload(kind, message, objectKey); err != nil {
		_ = p.store.MarkFailed(ctx, dispatchRecord.ID, err.Error())
		return jobs.Permanent(err)
	}

	result, err := p.provider.Send(ctx, ProviderRequest{
		DispatchType: kind,
		StudentID:    studentID.String(),
		Text:         strings.TrimSpace(message),
		ObjectKey:    strings.TrimSpace(objectKey),
		FileName:     strings.TrimSpace(readString(job.Payload, "file_name")),
		Metadata:     job.Payload,
	})
	if err != nil {
		_ = p.store.MarkFailed(ctx, dispatchRecord.ID, err.Error())
		if errors.Is(err, ErrMediaObjectNotFound) {
			return jobs.Permanent(err)
		}
		return err
	}
	if err := p.store.MarkSent(ctx, dispatchRecord.ID, result.ExternalMessageID); err != nil {
		return err
	}
	if err := removeMediaObject(objectKey); err != nil {
		return fmt.Errorf("cleanup media object: %w", err)
	}
	return nil
}

func normalizeDispatchType(kind string) string {
	switch strings.TrimSpace(strings.ToLower(kind)) {
	case "homework_digest", "homework_photo", "weekly_digest", "manual":
		return strings.TrimSpace(strings.ToLower(kind))
	default:
		return "manual"
	}
}

func readString(payload map[string]any, key string) string {
	if payload == nil {
		return ""
	}
	value, ok := payload[key]
	if !ok || value == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprintf("%v", value))
}
