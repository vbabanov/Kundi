package auth

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type RefreshSessionStore struct {
	pool *pgxpool.Pool
}

func NewRefreshSessionStore(pool *pgxpool.Pool) *RefreshSessionStore {
	return &RefreshSessionStore{pool: pool}
}

func (s *RefreshSessionStore) Create(
	ctx context.Context,
	studentID uuid.UUID,
	refreshTokenHash string,
	userAgent string,
	ipAddress string,
	expiresAt time.Time,
) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO auth_refresh_sessions (student_id, refresh_token_hash, user_agent, ip_address, expires_at)
		VALUES ($1, $2, $3, NULLIF($4, '')::inet, $5)
	`, studentID, refreshTokenHash, userAgent, ipAddress, expiresAt)
	return err
}

func (s *RefreshSessionStore) Revoke(ctx context.Context, refreshTokenHash string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE auth_refresh_sessions
		SET revoked_at = NOW()
		WHERE refresh_token_hash = $1 AND revoked_at IS NULL
	`, refreshTokenHash)
	return err
}

func (s *RefreshSessionStore) ResolveStudentID(ctx context.Context, refreshTokenHash string) (uuid.UUID, error) {
	var studentID uuid.UUID
	err := s.pool.QueryRow(ctx, `
		SELECT student_id
		FROM auth_refresh_sessions
		WHERE refresh_token_hash = $1
		  AND revoked_at IS NULL
		  AND expires_at > NOW()
	`, refreshTokenHash).Scan(&studentID)
	return studentID, err
}
