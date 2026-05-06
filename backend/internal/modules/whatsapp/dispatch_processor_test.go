package whatsapp

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/jobs"
)

type memoryDispatchStore struct {
	records map[string]DispatchRecord
	byKey   map[string]string
	status  map[string]string
}

func newMemoryDispatchStore() *memoryDispatchStore {
	return &memoryDispatchStore{
		records: make(map[string]DispatchRecord),
		byKey:   make(map[string]string),
		status:  make(map[string]string),
	}
}

func (m *memoryDispatchStore) UpsertPending(
	_ context.Context,
	_ uuid.UUID,
	_ string,
	_ map[string]any,
	idempotencyKey string,
) (DispatchRecord, bool, error) {
	if id, ok := m.byKey[idempotencyKey]; ok {
		record := m.records[id]
		record.Status = m.status[id]
		return record, false, nil
	}
	id := uuid.NewString()
	record := DispatchRecord{ID: id, Status: "pending", CreatedAt: time.Now().UTC()}
	m.byKey[idempotencyKey] = id
	m.records[id] = record
	m.status[id] = "pending"
	return record, true, nil
}

func (m *memoryDispatchStore) MarkSent(_ context.Context, id string, _ string) error {
	m.status[id] = "sent"
	return nil
}

func (m *memoryDispatchStore) MarkFailed(_ context.Context, id string, _ string) error {
	m.status[id] = "failed"
	return nil
}

type countingProvider struct {
	calls    int
	failOnce bool
}

func (p *countingProvider) Send(_ context.Context, _ ProviderRequest) (ProviderResult, error) {
	p.calls++
	if p.failOnce {
		p.failOnce = false
		return ProviderResult{}, errors.New("boom")
	}
	return ProviderResult{ExternalMessageID: "msg-1"}, nil
}

type scriptedProvider struct {
	sendFn func(req ProviderRequest) (ProviderResult, error)
}

func (p *scriptedProvider) Send(_ context.Context, req ProviderRequest) (ProviderResult, error) {
	if p.sendFn == nil {
		return ProviderResult{ExternalMessageID: "msg-scripted"}, nil
	}
	return p.sendFn(req)
}

func TestDispatchProcessorDuplicatePrevention(t *testing.T) {
	store := newMemoryDispatchStore()
	provider := &countingProvider{}
	processor := NewDispatchProcessor(store, provider)

	job := jobs.Job{
		ID:             "job-1",
		Type:           jobs.JobDispatchWhatsApp,
		IdempotencyKey: "dispatch-key",
		Payload: map[string]any{
			"kind":       "homework_digest",
			"student_id": "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
			"message":    "digest",
		},
	}

	if err := processor.HandleJob(context.Background(), job); err != nil {
		t.Fatalf("first dispatch failed: %v", err)
	}
	if err := processor.HandleJob(context.Background(), job); err != nil {
		t.Fatalf("second dispatch failed: %v", err)
	}
	if provider.calls != 1 {
		t.Fatalf("expected single provider call, got %d", provider.calls)
	}
}

func TestDispatchProcessorMarksFailure(t *testing.T) {
	store := newMemoryDispatchStore()
	provider := &countingProvider{failOnce: true}
	processor := NewDispatchProcessor(store, provider)

	job := jobs.Job{
		ID:             "job-2",
		Type:           jobs.JobDispatchWhatsApp,
		IdempotencyKey: "dispatch-key-2",
		Payload: map[string]any{
			"kind":       "homework_digest",
			"student_id": "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
			"message":    "digest",
		},
	}

	if err := processor.HandleJob(context.Background(), job); err == nil {
		t.Fatalf("expected provider error")
	}
	if provider.calls != 1 {
		t.Fatalf("expected one provider call, got %d", provider.calls)
	}
}

func TestDispatchProcessorMalformedPayloadIsPermanent(t *testing.T) {
	store := newMemoryDispatchStore()
	provider := &countingProvider{}
	processor := NewDispatchProcessor(store, provider)

	err := processor.HandleJob(context.Background(), jobs.Job{
		ID:             "job-3",
		Type:           jobs.JobDispatchWhatsApp,
		IdempotencyKey: "dispatch-key-3",
		Payload: map[string]any{
			"kind":       "homework_photo",
			"student_id": "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		},
	})
	if err == nil {
		t.Fatalf("expected malformed payload error")
	}
	if !jobs.IsPermanent(err) {
		t.Fatalf("expected permanent error, got %v", err)
	}
	if provider.calls != 0 {
		t.Fatalf("provider must not be called for malformed payload")
	}
}

func TestDispatchProcessorMissingMediaObjectIsPermanent(t *testing.T) {
	store := newMemoryDispatchStore()
	provider := &scriptedProvider{
		sendFn: func(_ ProviderRequest) (ProviderResult, error) {
			return ProviderResult{}, ErrMediaObjectNotFound
		},
	}
	processor := NewDispatchProcessor(store, provider)

	err := processor.HandleJob(context.Background(), jobs.Job{
		ID:             "job-4",
		Type:           jobs.JobDispatchWhatsApp,
		IdempotencyKey: "dispatch-key-4",
		Payload: map[string]any{
			"kind":       "homework_photo",
			"student_id": "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
			"file_name":  "lesson.jpg",
			"object_key": "file:///tmp/missing-photo.jpg",
		},
	})
	if err == nil {
		t.Fatalf("expected missing media error")
	}
	if !jobs.IsPermanent(err) {
		t.Fatalf("expected permanent error, got %v", err)
	}
}

func TestDispatchProcessorRemovesMediaObjectAfterSuccess(t *testing.T) {
	store := newMemoryDispatchStore()
	tmpDir := t.TempDir()
	tmpPhoto := filepath.Join(tmpDir, "photo.jpg")
	if err := os.WriteFile(tmpPhoto, []byte("temp-photo"), 0o600); err != nil {
		t.Fatalf("write temp photo: %v", err)
	}

	provider := &scriptedProvider{
		sendFn: func(req ProviderRequest) (ProviderResult, error) {
			if req.ObjectKey != "file://"+tmpPhoto {
				t.Fatalf("unexpected object key: %s", req.ObjectKey)
			}
			return ProviderResult{ExternalMessageID: "msg-photo-1"}, nil
		},
	}
	processor := NewDispatchProcessor(store, provider)

	err := processor.HandleJob(context.Background(), jobs.Job{
		ID:             "job-5",
		Type:           jobs.JobDispatchWhatsApp,
		IdempotencyKey: "dispatch-key-5",
		Payload: map[string]any{
			"kind":       "homework_photo",
			"student_id": "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
			"file_name":  "lesson.jpg",
			"object_key": "file://" + tmpPhoto,
			"message":    "caption",
		},
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if _, statErr := os.Stat(tmpPhoto); !os.IsNotExist(statErr) {
		t.Fatalf("expected temp photo to be removed, stat err=%v", statErr)
	}
}
