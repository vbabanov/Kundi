package whatsapp

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type DispatchRecord struct {
	ID        string
	Status    string
	CreatedAt time.Time
}

type DispatchStore interface {
	UpsertPending(
		ctx context.Context,
		studentID uuid.UUID,
		dispatchType string,
		payload map[string]any,
		idempotencyKey string,
	) (DispatchRecord, bool, error)
	MarkSent(ctx context.Context, id string, externalMessageID string) error
	MarkFailed(ctx context.Context, id string, reason string) error
}

type PostgresDispatchStore struct {
	pool *pgxpool.Pool
}

func NewPostgresDispatchStore(pool *pgxpool.Pool) *PostgresDispatchStore {
	return &PostgresDispatchStore{pool: pool}
}

func (s *PostgresDispatchStore) UpsertPending(
	ctx context.Context,
	studentID uuid.UUID,
	dispatchType string,
	payload map[string]any,
	idempotencyKey string,
) (DispatchRecord, bool, error) {
	rawPayload, _ := json.Marshal(payload)
	kind := strings.TrimSpace(dispatchType)
	if kind == "" {
		kind = "manual"
	}

	var record DispatchRecord
	err := s.pool.QueryRow(ctx, `
		INSERT INTO whatsapp_dispatches (
			student_id,
			dispatch_type,
			channel,
			payload,
			status,
			idempotency_key
		)
		VALUES ($1, $2, 'whatsapp', $3, 'pending', $4)
		ON CONFLICT (idempotency_key) DO NOTHING
		RETURNING id::text, status, created_at
	`, studentID, kind, rawPayload, idempotencyKey).Scan(&record.ID, &record.Status, &record.CreatedAt)
	if err == pgx.ErrNoRows {
		if err := s.pool.QueryRow(ctx, `
			SELECT id::text, status, created_at
			FROM whatsapp_dispatches
			WHERE idempotency_key = $1
		`, idempotencyKey).Scan(&record.ID, &record.Status, &record.CreatedAt); err != nil {
			return DispatchRecord{}, false, err
		}
		return record, false, nil
	}
	if err != nil {
		return DispatchRecord{}, false, err
	}
	return record, true, nil
}

func (s *PostgresDispatchStore) MarkSent(ctx context.Context, id string, externalMessageID string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE whatsapp_dispatches
		SET status = 'sent',
			sent_at = NOW(),
			payload = jsonb_set(payload, '{provider_message_id}', to_jsonb($2::text), true)
		WHERE id = $1::uuid
	`, id, externalMessageID)
	if err != nil {
		return fmt.Errorf("mark dispatch sent: %w", err)
	}
	return nil
}

func (s *PostgresDispatchStore) MarkFailed(ctx context.Context, id string, reason string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE whatsapp_dispatches
		SET status = 'failed',
			payload = jsonb_set(payload, '{last_error}', to_jsonb($2::text), true)
		WHERE id = $1::uuid
	`, id, reason)
	if err != nil {
		return fmt.Errorf("mark dispatch failed: %w", err)
	}
	return nil
}
