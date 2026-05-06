package jobs

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository interface {
	Enqueue(ctx context.Context, req EnqueueRequest) (string, bool, error)
	LeaseNext(ctx context.Context, worker string, leaseDuration time.Duration) (*Job, error)
	Complete(ctx context.Context, jobID string) error
	Fail(ctx context.Context, jobID string, worker string, err error) (bool, error)
	GetStatus(ctx context.Context, jobID string) (*JobStatusRecord, error)
}

type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

func (r *PostgresRepository) Enqueue(ctx context.Context, req EnqueueRequest) (string, bool, error) {
	payload, _ := json.Marshal(req.Payload)
	var id uuid.UUID
	err := r.pool.QueryRow(ctx, `
		INSERT INTO jobs (job_type, idempotency_key, payload, priority, status, available_at)
		VALUES ($1, $2, $3, $4, 'queued', NOW())
		ON CONFLICT (job_type, idempotency_key) DO NOTHING
		RETURNING id
	`, req.Type, req.IdempotencyKey, payload, req.Priority).Scan(&id)
	if err == pgx.ErrNoRows {
		var existingID uuid.UUID
		err = r.pool.QueryRow(ctx, `SELECT id FROM jobs WHERE job_type = $1 AND idempotency_key = $2`, req.Type, req.IdempotencyKey).Scan(&existingID)
		if err != nil {
			return "", false, err
		}
		return existingID.String(), false, nil
	}
	if err != nil {
		return "", false, err
	}
	return id.String(), true, nil
}

func (r *PostgresRepository) LeaseNext(ctx context.Context, worker string, leaseDuration time.Duration) (*Job, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var job Job
	var payloadRaw []byte
	err = tx.QueryRow(ctx, `
		WITH candidate AS (
			SELECT id
			FROM jobs
			WHERE (status = 'queued' AND available_at <= NOW())
			   OR (status = 'leased' AND lease_until IS NOT NULL AND lease_until <= NOW())
			ORDER BY priority ASC, created_at ASC
			FOR UPDATE SKIP LOCKED
			LIMIT 1
		)
		UPDATE jobs j
		SET status = 'leased',
			lease_owner = $1,
			lease_until = NOW() + make_interval(secs => $2::int),
			updated_at = NOW()
		FROM candidate c
		WHERE j.id = c.id
		RETURNING j.id::text, j.job_type, j.idempotency_key, j.payload, j.status, j.attempts, j.max_attempts, COALESCE(j.lease_owner, ''), COALESCE(j.lease_until, NOW())
	`, worker, int(leaseDuration.Seconds())).Scan(
		&job.ID,
		&job.Type,
		&job.IdempotencyKey,
		&payloadRaw,
		&job.Status,
		&job.Attempts,
		&job.MaxAttempts,
		&job.LeaseOwner,
		&job.LeaseUntil,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if len(payloadRaw) > 0 {
		_ = json.Unmarshal(payloadRaw, &job.Payload)
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &job, nil
}

func (r *PostgresRepository) Complete(ctx context.Context, jobID string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE jobs
		SET status = 'succeeded', finished_at = NOW(), lease_owner = NULL, lease_until = NULL, updated_at = NOW()
		WHERE id = $1::uuid
	`, jobID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("job not found")
	}
	return nil
}

func (r *PostgresRepository) Fail(ctx context.Context, jobID string, worker string, jobErr error) (bool, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx)

	var currentAttempts int
	var maxAttempts int
	err = tx.QueryRow(ctx, `
		SELECT attempts, max_attempts
		FROM jobs
		WHERE id = $1::uuid
		FOR UPDATE
	`, jobID).Scan(&currentAttempts, &maxAttempts)
	if err != nil {
		return false, err
	}

	attempts := currentAttempts + 1
	finalFailure := attempts >= maxAttempts || IsPermanent(jobErr)
	availableAt := time.Now().UTC()
	if !finalFailure {
		availableAt = availableAt.Add(retryBackoff(attempts))
	}

	_, err = tx.Exec(ctx, `
		UPDATE jobs
		SET attempts = $1,
			last_error = $2,
			status = CASE WHEN $3 THEN 'dead_letter' ELSE 'queued' END,
			available_at = $4,
			lease_owner = NULL,
			lease_until = NULL,
			updated_at = NOW(),
			finished_at = CASE WHEN $3 THEN NOW() ELSE finished_at END
		WHERE id = $5::uuid
	`, attempts, jobErr.Error(), finalFailure, availableAt, jobID)
	if err != nil {
		return false, err
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO job_attempts (job_id, attempt_no, started_at, finished_at, success, error_message, worker_name)
		VALUES ($1::uuid, $2, NOW(), NOW(), FALSE, $3, $4)
	`, jobID, attempts, jobErr.Error(), worker)
	if err != nil {
		return false, fmt.Errorf("insert job attempt: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return false, err
	}
	return finalFailure, nil
}

func (r *PostgresRepository) GetStatus(ctx context.Context, jobID string) (*JobStatusRecord, error) {
	var record JobStatusRecord
	err := r.pool.QueryRow(ctx, `
		SELECT id::text,
		       job_type,
		       status,
		       attempts,
		       max_attempts,
		       COALESCE(last_error, ''),
		       COALESCE(finished_at, '0001-01-01T00:00:00Z'::timestamptz)
		FROM jobs
		WHERE id = $1::uuid
	`, jobID).Scan(
		&record.ID,
		&record.Type,
		&record.Status,
		&record.Attempts,
		&record.MaxAttempts,
		&record.LastError,
		&record.FinishedAt,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &record, nil
}

func retryBackoff(attempt int) time.Duration {
	if attempt <= 1 {
		return 15 * time.Second
	}
	seconds := 15 * attempt * attempt
	if seconds > 300 {
		seconds = 300
	}
	return time.Duration(seconds) * time.Second
}
