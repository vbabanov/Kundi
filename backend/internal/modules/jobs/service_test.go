package jobs

import (
	"context"
	"testing"
	"time"
)

type fakeRepository struct {
	statusRecord *JobStatusRecord
	statusJobID  string
}

func (f *fakeRepository) Enqueue(_ context.Context, _ EnqueueRequest) (string, bool, error) {
	return "", false, nil
}

func (f *fakeRepository) LeaseNext(_ context.Context, _ string, _ time.Duration) (*Job, error) {
	return nil, nil
}

func (f *fakeRepository) Complete(_ context.Context, _ string) error {
	return nil
}

func (f *fakeRepository) Fail(_ context.Context, _ string, _ string, _ error) (bool, error) {
	return false, nil
}

func (f *fakeRepository) GetStatus(_ context.Context, jobID string) (*JobStatusRecord, error) {
	f.statusJobID = jobID
	return f.statusRecord, nil
}

func TestGetStatusRequiresJobID(t *testing.T) {
	service := NewService(&fakeRepository{})
	_, err := service.GetStatus(context.Background(), " ")
	if err == nil {
		t.Fatalf("expected validation error")
	}
}

func TestGetStatusReadsRepository(t *testing.T) {
	repo := &fakeRepository{
		statusRecord: &JobStatusRecord{
			ID:        "job-1",
			Status:    StatusQueued,
			LastError: "",
		},
	}
	service := NewService(repo)
	record, err := service.GetStatus(context.Background(), "job-1")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if record == nil || record.ID != "job-1" {
		t.Fatalf("unexpected record: %#v", record)
	}
	if repo.statusJobID != "job-1" {
		t.Fatalf("expected repo to receive job id")
	}
}
