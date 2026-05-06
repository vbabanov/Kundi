package integration

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/jobs"
	whatsappmodule "github.com/kundi/kundi/backend/internal/modules/whatsapp"
)

type memoryJobsRepository struct {
	mu               sync.Mutex
	now              time.Time
	seq              int
	defaultMax       int
	byTypeAndKey     map[string]string
	recordsByID      map[string]*memoryJobRecord
	creationOrdering []string
}

type memoryJobRecord struct {
	job        jobs.Job
	priority   int
	available  time.Time
	createdAt  time.Time
	lastError  string
	finishedAt time.Time
}

func newMemoryJobsRepository(now time.Time) *memoryJobsRepository {
	return &memoryJobsRepository{
		now:              now.UTC(),
		defaultMax:       3,
		byTypeAndKey:     make(map[string]string),
		recordsByID:      make(map[string]*memoryJobRecord),
		creationOrdering: make([]string, 0),
	}
}

func (r *memoryJobsRepository) Enqueue(_ context.Context, req jobs.EnqueueRequest) (string, bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	key := string(req.Type) + "::" + req.IdempotencyKey
	if id, exists := r.byTypeAndKey[key]; exists {
		return id, false, nil
	}
	r.seq++
	id := fmt.Sprintf("job-%d", r.seq)
	priority := req.Priority
	if priority <= 0 {
		priority = 50
	}
	record := &memoryJobRecord{
		job: jobs.Job{
			ID:             id,
			Type:           req.Type,
			IdempotencyKey: req.IdempotencyKey,
			Payload:        req.Payload,
			Status:         jobs.StatusQueued,
			Attempts:       0,
			MaxAttempts:    r.defaultMax,
		},
		priority:  priority,
		available: r.now,
		createdAt: r.now,
	}
	r.byTypeAndKey[key] = id
	r.recordsByID[id] = record
	r.creationOrdering = append(r.creationOrdering, id)
	return id, true, nil
}

func (r *memoryJobsRepository) LeaseNext(_ context.Context, worker string, leaseDuration time.Duration) (*jobs.Job, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	var selected *memoryJobRecord
	for _, id := range r.creationOrdering {
		record := r.recordsByID[id]
		if record == nil {
			continue
		}
		if !r.isLeasable(record, r.now) {
			continue
		}
		if selected == nil || record.priority < selected.priority {
			selected = record
			continue
		}
		if selected != nil && record.priority == selected.priority && record.createdAt.Before(selected.createdAt) {
			selected = record
		}
	}
	if selected == nil {
		return nil, nil
	}
	selected.job.Status = jobs.StatusLeased
	selected.job.LeaseOwner = worker
	selected.job.LeaseUntil = r.now.Add(leaseDuration)
	jobCopy := selected.job
	return &jobCopy, nil
}

func (r *memoryJobsRepository) Complete(_ context.Context, jobID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	record := r.recordsByID[jobID]
	if record == nil {
		return errors.New("job not found")
	}
	record.job.Status = jobs.StatusSucceeded
	record.job.LeaseOwner = ""
	record.job.LeaseUntil = time.Time{}
	record.finishedAt = r.now
	return nil
}

func (r *memoryJobsRepository) Fail(_ context.Context, jobID string, worker string, err error) (bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	record := r.recordsByID[jobID]
	if record == nil {
		return false, errors.New("job not found")
	}
	record.job.Attempts++
	record.lastError = err.Error()
	record.job.LeaseOwner = ""
	record.job.LeaseUntil = time.Time{}
	if record.job.Attempts >= record.job.MaxAttempts {
		record.job.Status = jobs.StatusDeadLetter
		record.finishedAt = r.now
		return true, nil
	}
	record.job.Status = jobs.StatusQueued
	record.available = r.now.Add(memoryRetryBackoff(record.job.Attempts))
	_ = worker
	return false, nil
}

func (r *memoryJobsRepository) GetStatus(_ context.Context, jobID string) (*jobs.JobStatusRecord, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	record := r.recordsByID[jobID]
	if record == nil {
		return nil, nil
	}
	return &jobs.JobStatusRecord{
		ID:          record.job.ID,
		Type:        record.job.Type,
		Status:      record.job.Status,
		Attempts:    record.job.Attempts,
		MaxAttempts: record.job.MaxAttempts,
		LastError:   record.lastError,
		FinishedAt:  record.finishedAt,
	}, nil
}

func (r *memoryJobsRepository) advance(duration time.Duration) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.now = r.now.Add(duration)
}

func (r *memoryJobsRepository) isLeasable(record *memoryJobRecord, now time.Time) bool {
	if record.job.Status == jobs.StatusQueued {
		return !record.available.After(now)
	}
	if record.job.Status == jobs.StatusLeased {
		return !record.job.LeaseUntil.After(now)
	}
	return false
}

func (r *memoryJobsRepository) status(jobID string) jobs.Status {
	r.mu.Lock()
	defer r.mu.Unlock()
	record := r.recordsByID[jobID]
	if record == nil {
		return ""
	}
	return record.job.Status
}

func memoryRetryBackoff(attempt int) time.Duration {
	if attempt <= 1 {
		return 15 * time.Second
	}
	seconds := 15 * attempt * attempt
	if seconds > 300 {
		seconds = 300
	}
	return time.Duration(seconds) * time.Second
}

type memoryDispatchStore struct {
	mu      sync.Mutex
	byID    map[string]whatsappmodule.DispatchRecord
	byKey   map[string]string
	status  map[string]string
	counter int
}

func newMemoryDispatchStore() *memoryDispatchStore {
	return &memoryDispatchStore{
		byID:   make(map[string]whatsappmodule.DispatchRecord),
		byKey:  make(map[string]string),
		status: make(map[string]string),
	}
}

func (m *memoryDispatchStore) UpsertPending(
	_ context.Context,
	_ uuid.UUID,
	_ string,
	_ map[string]any,
	idempotencyKey string,
) (whatsappmodule.DispatchRecord, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if id, exists := m.byKey[idempotencyKey]; exists {
		record := m.byID[id]
		record.Status = m.status[id]
		return record, false, nil
	}
	m.counter++
	id := fmt.Sprintf("dispatch-%d", m.counter)
	record := whatsappmodule.DispatchRecord{
		ID:        id,
		Status:    "pending",
		CreatedAt: time.Now().UTC(),
	}
	m.byID[id] = record
	m.byKey[idempotencyKey] = id
	m.status[id] = "pending"
	return record, true, nil
}

func (m *memoryDispatchStore) MarkSent(_ context.Context, id string, _ string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.status[id] = "sent"
	return nil
}

func (m *memoryDispatchStore) MarkFailed(_ context.Context, id string, _ string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.status[id] = "failed"
	return nil
}

func (m *memoryDispatchStore) statusByKey(key string) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	id := m.byKey[key]
	return m.status[id]
}

type scriptedProvider struct {
	mu      sync.Mutex
	failSeq []bool
	calls   int
}

func (p *scriptedProvider) Send(_ context.Context, _ whatsappmodule.ProviderRequest) (whatsappmodule.ProviderResult, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.calls++
	fail := false
	if len(p.failSeq) >= p.calls {
		fail = p.failSeq[p.calls-1]
	}
	if fail {
		return whatsappmodule.ProviderResult{}, errors.New("provider failed")
	}
	return whatsappmodule.ProviderResult{ExternalMessageID: fmt.Sprintf("msg-%d", p.calls)}, nil
}

func TestWhatsAppJobHappyPath(t *testing.T) {
	repo := newMemoryJobsRepository(time.Date(2026, 3, 30, 12, 0, 0, 0, time.UTC))
	jobsSvc := jobs.NewService(repo)
	whatsappSvc := whatsappmodule.NewService(jobsSvc)
	store := newMemoryDispatchStore()
	provider := &scriptedProvider{failSeq: []bool{false}}
	dispatch := whatsappmodule.NewDispatchProcessor(store, provider)

	jobID, created, err := whatsappSvc.SendHomeworkDigest(
		context.Background(),
		"8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		"2026-03-30",
		"homework",
		"digest-key-1",
	)
	if err != nil {
		t.Fatalf("enqueue digest job failed: %v", err)
	}
	if !created {
		t.Fatalf("expected first enqueue to create a job")
	}

	runDispatchOnce(t, repo, dispatch, "worker-whatsapp", 30*time.Second)
	if repo.status(jobID) != jobs.StatusSucceeded {
		t.Fatalf("expected succeeded status, got %s", repo.status(jobID))
	}
	if store.statusByKey("digest-key-1") != "sent" {
		t.Fatalf("expected dispatch status sent")
	}
	if provider.calls != 1 {
		t.Fatalf("expected 1 provider call, got %d", provider.calls)
	}
}

func TestWhatsAppExpiredLeaseReclaim(t *testing.T) {
	repo := newMemoryJobsRepository(time.Date(2026, 3, 30, 12, 0, 0, 0, time.UTC))
	_, _, _ = repo.Enqueue(context.Background(), jobs.EnqueueRequest{
		Type:           jobs.JobDispatchWhatsApp,
		IdempotencyKey: "lease-key-1",
		Payload: map[string]any{
			"kind":       "homework_digest",
			"student_id": "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
			"message":    "digest",
		},
	})

	leasedByOne, err := repo.LeaseNext(context.Background(), "worker-1", 5*time.Second)
	if err != nil || leasedByOne == nil {
		t.Fatalf("expected first lease: err=%v", err)
	}
	repo.advance(6 * time.Second)
	leasedByTwo, err := repo.LeaseNext(context.Background(), "worker-2", 5*time.Second)
	if err != nil || leasedByTwo == nil {
		t.Fatalf("expected reclaimed lease: err=%v", err)
	}
	if leasedByOne.ID != leasedByTwo.ID {
		t.Fatalf("expected same job reclaimed, got %s vs %s", leasedByOne.ID, leasedByTwo.ID)
	}
}

func TestWhatsAppRetryThenSuccess(t *testing.T) {
	repo := newMemoryJobsRepository(time.Date(2026, 3, 30, 12, 0, 0, 0, time.UTC))
	jobsSvc := jobs.NewService(repo)
	whatsappSvc := whatsappmodule.NewService(jobsSvc)
	store := newMemoryDispatchStore()
	provider := &scriptedProvider{failSeq: []bool{true, false}}
	dispatch := whatsappmodule.NewDispatchProcessor(store, provider)

	jobID, _, err := whatsappSvc.SendHomeworkDigest(
		context.Background(),
		"8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		"2026-03-30",
		"homework",
		"retry-key-1",
	)
	if err != nil {
		t.Fatalf("enqueue digest job failed: %v", err)
	}

	runDispatchOnceAllowFail(t, repo, dispatch, "worker-whatsapp", 30*time.Second)
	if repo.status(jobID) != jobs.StatusQueued {
		t.Fatalf("expected job queued after first failure, got %s", repo.status(jobID))
	}
	repo.advance(15 * time.Second)
	runDispatchOnce(t, repo, dispatch, "worker-whatsapp", 30*time.Second)

	if repo.status(jobID) != jobs.StatusSucceeded {
		t.Fatalf("expected succeeded after retry, got %s", repo.status(jobID))
	}
	if provider.calls != 2 {
		t.Fatalf("expected 2 provider calls, got %d", provider.calls)
	}
}

func TestWhatsAppRetryThenDeadLetter(t *testing.T) {
	repo := newMemoryJobsRepository(time.Date(2026, 3, 30, 12, 0, 0, 0, time.UTC))
	repo.defaultMax = 2
	jobsSvc := jobs.NewService(repo)
	whatsappSvc := whatsappmodule.NewService(jobsSvc)
	store := newMemoryDispatchStore()
	provider := &scriptedProvider{failSeq: []bool{true, true, true}}
	dispatch := whatsappmodule.NewDispatchProcessor(store, provider)

	jobID, _, err := whatsappSvc.SendHomeworkDigest(
		context.Background(),
		"8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		"2026-03-30",
		"homework",
		"dead-letter-key-1",
	)
	if err != nil {
		t.Fatalf("enqueue digest job failed: %v", err)
	}

	runDispatchOnceAllowFail(t, repo, dispatch, "worker-whatsapp", 30*time.Second)
	repo.advance(15 * time.Second)
	runDispatchOnceAllowFail(t, repo, dispatch, "worker-whatsapp", 30*time.Second)

	if repo.status(jobID) != jobs.StatusDeadLetter {
		t.Fatalf("expected dead_letter status, got %s", repo.status(jobID))
	}
}

func TestWhatsAppDuplicateDispatchPrevention(t *testing.T) {
	repo := newMemoryJobsRepository(time.Date(2026, 3, 30, 12, 0, 0, 0, time.UTC))
	jobsSvc := jobs.NewService(repo)
	whatsappSvc := whatsappmodule.NewService(jobsSvc)
	store := newMemoryDispatchStore()
	provider := &scriptedProvider{failSeq: []bool{false}}
	dispatch := whatsappmodule.NewDispatchProcessor(store, provider)

	firstID, firstCreated, err := whatsappSvc.SendHomeworkDigest(
		context.Background(),
		"8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		"2026-03-30",
		"homework",
		"duplicate-key-1",
	)
	if err != nil {
		t.Fatalf("first enqueue failed: %v", err)
	}
	secondID, secondCreated, err := whatsappSvc.SendHomeworkDigest(
		context.Background(),
		"8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		"2026-03-30",
		"homework",
		"duplicate-key-1",
	)
	if err != nil {
		t.Fatalf("second enqueue failed: %v", err)
	}
	if !firstCreated || secondCreated {
		t.Fatalf("expected first create=true and second create=false")
	}
	if firstID != secondID {
		t.Fatalf("expected same job id for duplicate idempotency key")
	}

	runDispatchOnce(t, repo, dispatch, "worker-whatsapp", 30*time.Second)
	if provider.calls != 1 {
		t.Fatalf("expected one provider call for duplicate enqueues, got %d", provider.calls)
	}
}

func runDispatchOnce(t *testing.T, repo jobs.Repository, dispatch *whatsappmodule.DispatchProcessor, worker string, lease time.Duration) {
	t.Helper()
	job, err := repo.LeaseNext(context.Background(), worker, lease)
	if err != nil {
		t.Fatalf("lease next failed: %v", err)
	}
	if job == nil {
		t.Fatalf("expected leased job but queue is empty")
	}
	if err := dispatch.HandleJob(context.Background(), *job); err != nil {
		t.Fatalf("dispatch handler failed: %v", err)
	}
	if err := repo.Complete(context.Background(), job.ID); err != nil {
		t.Fatalf("complete job failed: %v", err)
	}
}

func runDispatchOnceAllowFail(t *testing.T, repo jobs.Repository, dispatch *whatsappmodule.DispatchProcessor, worker string, lease time.Duration) {
	t.Helper()
	job, err := repo.LeaseNext(context.Background(), worker, lease)
	if err != nil {
		t.Fatalf("lease next failed: %v", err)
	}
	if job == nil {
		t.Fatalf("expected leased job but queue is empty")
	}
	if err := dispatch.HandleJob(context.Background(), *job); err != nil {
		_, failErr := repo.Fail(context.Background(), job.ID, worker, err)
		if failErr != nil {
			t.Fatalf("fail transition failed: %v", failErr)
		}
		return
	}
	if err := repo.Complete(context.Background(), job.ID); err != nil {
		t.Fatalf("complete job failed: %v", err)
	}
}
