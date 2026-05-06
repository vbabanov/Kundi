package audit

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Service struct {
	pool *pgxpool.Pool
}

func NewService(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool}
}

func (s *Service) Log(ctx context.Context, action string, entityType string, entityID string, studentID string, metadata map[string]any) error {
	raw, _ := json.Marshal(metadata)
	_, err := s.pool.Exec(ctx, `
		INSERT INTO audit_log (action, entity_type, entity_id, actor_student_id, metadata)
		VALUES ($1, $2, $3, NULLIF($4, '')::uuid, $5)
	`, action, entityType, entityID, studentID, raw)
	return err
}
