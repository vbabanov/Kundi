package jobs

import "time"

type JobType string

const (
	JobIngestPostProcessing JobType = "ingest_post_processing"
	JobRecomputeDailyStats  JobType = "recompute_daily_stats"
	JobRecomputeWeeklyStats JobType = "recompute_weekly_stats"
	JobGenerateParentDigest JobType = "generate_parent_digest"
	JobDispatchWhatsApp     JobType = "dispatch_whatsapp"
	JobAIPostProcessing     JobType = "ai_post_processing"
	JobStaleDataDetection   JobType = "stale_data_detection"
)

type Status string

const (
	StatusQueued     Status = "queued"
	StatusLeased     Status = "leased"
	StatusSucceeded  Status = "succeeded"
	StatusFailed     Status = "failed"
	StatusDeadLetter Status = "dead_letter"
)

type Job struct {
	ID             string         `json:"id"`
	Type           JobType        `json:"type"`
	IdempotencyKey string         `json:"idempotency_key"`
	Payload        map[string]any `json:"payload"`
	Status         Status         `json:"status"`
	Attempts       int            `json:"attempts"`
	MaxAttempts    int            `json:"max_attempts"`
	LeaseOwner     string         `json:"lease_owner"`
	LeaseUntil     time.Time      `json:"lease_until"`
}

type JobStatusRecord struct {
	ID          string    `json:"id"`
	Type        JobType   `json:"type"`
	Status      Status    `json:"status"`
	Attempts    int       `json:"attempts"`
	MaxAttempts int       `json:"max_attempts"`
	LastError   string    `json:"last_error"`
	FinishedAt  time.Time `json:"finished_at"`
}

type EnqueueRequest struct {
	Type           JobType
	IdempotencyKey string
	Payload        map[string]any
	Priority       int
}
