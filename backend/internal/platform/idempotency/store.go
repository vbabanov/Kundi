package idempotency

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Entry struct {
	Scope      string
	Key        string
	StatusCode int
	Body       map[string]any
	ExpiresAt  time.Time
}

type Store struct {
	pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool}
}

func (s *Store) Load(ctx context.Context, scope, key string) (*Entry, error) {
	var raw []byte
	var out Entry
	err := s.pool.QueryRow(ctx, `
		SELECT scope, idempotency_key, COALESCE(response_status, 0), response_body, expires_at
		FROM api_idempotency_keys
		WHERE scope = $1 AND idempotency_key = $2 AND expires_at > NOW()
	`, scope, key).Scan(&out.Scope, &out.Key, &out.StatusCode, &raw, &out.ExpiresAt)
	if err != nil {
		return nil, err
	}
	if len(raw) > 0 {
		_ = json.Unmarshal(raw, &out.Body)
	}
	return &out, nil
}

func (s *Store) Save(ctx context.Context, entry Entry) error {
	body, _ := json.Marshal(entry.Body)
	_, err := s.pool.Exec(ctx, `
		INSERT INTO api_idempotency_keys (scope, idempotency_key, response_status, response_body, expires_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (scope, idempotency_key)
		DO UPDATE SET response_status = EXCLUDED.response_status, response_body = EXCLUDED.response_body, expires_at = EXCLUDED.expires_at
	`, entry.Scope, entry.Key, entry.StatusCode, body, entry.ExpiresAt)
	return err
}
