package auth

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/crypto"
	"github.com/kundi/kundi/backend/internal/platform/validate"
)

type Service struct {
	repo         AccountRepository
	cipher       *crypto.FieldCipher
	accessTokens *platformauth.AccessTokenService
	sessions     RefreshSessionStore
	refreshTTL   time.Duration
}

type RefreshSessionStore interface {
	Create(
		ctx context.Context,
		studentID uuid.UUID,
		refreshTokenHash string,
		userAgent string,
		ipAddress string,
		expiresAt time.Time,
	) error
	Revoke(ctx context.Context, refreshTokenHash string) error
	ResolveStudentID(ctx context.Context, refreshTokenHash string) (uuid.UUID, error)
}

func NewService(
	repo AccountRepository,
	cipher *crypto.FieldCipher,
	accessTokens *platformauth.AccessTokenService,
	sessions RefreshSessionStore,
	refreshTTL time.Duration,
) *Service {
	return &Service{
		repo:         repo,
		cipher:       cipher,
		accessTokens: accessTokens,
		sessions:     sessions,
		refreshTTL:   refreshTTL,
	}
}

func (s *Service) Login(ctx context.Context, cmd LoginCommand) (LoginResult, error) {
	if !validate.Source(cmd.Source) {
		return LoginResult{}, apperrors.BadRequest("invalid_source", "source is not supported")
	}
	if !validate.Required(cmd.Login) || !validate.Required(cmd.Password) {
		return LoginResult{}, apperrors.BadRequest("missing_credentials", "login and password are required")
	}
	if !validate.MaxLen(cmd.Login, 256) || !validate.MaxLen(cmd.Password, 256) {
		return LoginResult{}, apperrors.BadRequest("invalid_credentials", "credential length is invalid")
	}

	loginCipher, err := s.cipher.Encrypt(strings.TrimSpace(cmd.Login))
	if err != nil {
		return LoginResult{}, apperrors.Internal("cipher_error", "failed to encrypt login", err)
	}
	passwordCipher, err := s.cipher.Encrypt(cmd.Password)
	if err != nil {
		return LoginResult{}, apperrors.Internal("cipher_error", "failed to encrypt password", err)
	}

	fingerprint := loginFingerprint(cmd.Source, cmd.Login)
	studentID, _, err := s.repo.UpsertDiaryAccount(ctx, cmd.Source, fingerprint, loginCipher, passwordCipher)
	if err != nil {
		return LoginResult{}, apperrors.Internal("auth_store_failed", "failed to persist diary account", err)
	}

	now := time.Now().UTC()
	accessToken, claims, err := s.accessTokens.Issue(studentID, now)
	if err != nil {
		return LoginResult{}, apperrors.Internal("token_issue_failed", "failed to issue access token", err)
	}

	refreshToken, err := platformauth.GenerateRefreshToken()
	if err != nil {
		return LoginResult{}, apperrors.Internal("token_issue_failed", "failed to issue refresh token", err)
	}
	refreshHash := platformauth.HashRefreshToken(refreshToken)
	if err := s.sessions.Create(
		ctx,
		studentID,
		refreshHash,
		cmd.UserAgent,
		cmd.IPAddress,
		now.Add(s.refreshTTL),
	); err != nil {
		return LoginResult{}, apperrors.Internal("refresh_session_failed", "failed to persist refresh session", err)
	}

	return LoginResult{
		StudentID:    studentID.String(),
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresAtISO: time.Unix(claims.ExpiresAt, 0).UTC().Format(time.RFC3339),
	}, nil
}

func (s *Service) RotateRefreshToken(
	ctx context.Context,
	refreshToken string,
	userAgent string,
	ipAddress string,
) (LoginResult, error) {
	hash := platformauth.HashRefreshToken(strings.TrimSpace(refreshToken))
	studentID, err := s.sessions.ResolveStudentID(ctx, hash)
	if err != nil {
		return LoginResult{}, apperrors.Unauthorized("invalid_refresh_token", "refresh token is invalid")
	}
	if err := s.sessions.Revoke(ctx, hash); err != nil {
		return LoginResult{}, apperrors.Internal("refresh_revoke_failed", "failed to revoke previous refresh session", err)
	}
	newRefreshToken, err := platformauth.GenerateRefreshToken()
	if err != nil {
		return LoginResult{}, apperrors.Internal("token_issue_failed", "failed to issue refresh token", err)
	}
	newRefreshHash := platformauth.HashRefreshToken(newRefreshToken)
	if err := s.sessions.Create(ctx, studentID, newRefreshHash, userAgent, ipAddress, time.Now().UTC().Add(s.refreshTTL)); err != nil {
		return LoginResult{}, apperrors.Internal("refresh_session_failed", "failed to persist refresh session", err)
	}
	accessToken, claims, err := s.accessTokens.Issue(studentID, time.Now().UTC())
	if err != nil {
		return LoginResult{}, apperrors.Internal("token_issue_failed", "failed to issue access token", err)
	}

	return LoginResult{
		StudentID:    studentID.String(),
		AccessToken:  accessToken,
		RefreshToken: newRefreshToken,
		ExpiresAtISO: time.Unix(claims.ExpiresAt, 0).UTC().Format(time.RFC3339),
	}, nil
}

func loginFingerprint(source, login string) string {
	payload := strings.ToLower(strings.TrimSpace(source)) + ":" + strings.ToLower(strings.TrimSpace(login))
	sum := sha256.Sum256([]byte(payload))
	return hex.EncodeToString(sum[:])
}

func ParseStudentID(value string) (uuid.UUID, error) {
	id, err := uuid.Parse(strings.TrimSpace(value))
	if err != nil {
		return uuid.Nil, fmt.Errorf("invalid student id: %w", err)
	}
	return id, nil
}
