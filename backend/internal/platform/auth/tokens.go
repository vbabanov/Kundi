package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

type AccessClaims struct {
	StudentID string `json:"student_id"`
	IssuedAt  int64  `json:"iat"`
	ExpiresAt int64  `json:"exp"`
}

type AccessTokenService struct {
	secret []byte
	ttl    time.Duration
}

func NewAccessTokenService(secret string, ttl time.Duration) *AccessTokenService {
	return &AccessTokenService{secret: []byte(secret), ttl: ttl}
}

func (s *AccessTokenService) Issue(studentID uuid.UUID, now time.Time) (token string, claims AccessClaims, err error) {
	claims = AccessClaims{
		StudentID: studentID.String(),
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(s.ttl).Unix(),
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", AccessClaims{}, err
	}
	encodedPayload := base64.RawURLEncoding.EncodeToString(payload)
	sig := s.sign(encodedPayload)
	return encodedPayload + "." + base64.RawURLEncoding.EncodeToString(sig), claims, nil
}

func (s *AccessTokenService) Parse(token string) (AccessClaims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return AccessClaims{}, errors.New("invalid token format")
	}
	payloadPart, sigPart := parts[0], parts[1]
	decodedSig, err := base64.RawURLEncoding.DecodeString(sigPart)
	if err != nil {
		return AccessClaims{}, errors.New("invalid signature encoding")
	}
	expected := s.sign(payloadPart)
	if !hmac.Equal(decodedSig, expected) {
		return AccessClaims{}, errors.New("invalid signature")
	}
	payloadBytes, err := base64.RawURLEncoding.DecodeString(payloadPart)
	if err != nil {
		return AccessClaims{}, errors.New("invalid payload encoding")
	}
	var claims AccessClaims
	if err := json.Unmarshal(payloadBytes, &claims); err != nil {
		return AccessClaims{}, fmt.Errorf("invalid payload: %w", err)
	}
	if time.Now().UTC().Unix() >= claims.ExpiresAt {
		return AccessClaims{}, errors.New("token expired")
	}
	if _, err := uuid.Parse(claims.StudentID); err != nil {
		return AccessClaims{}, errors.New("invalid student id")
	}
	return claims, nil
}

func (s *AccessTokenService) sign(payload string) []byte {
	h := hmac.New(sha256.New, s.secret)
	_, _ = h.Write([]byte(payload))
	return h.Sum(nil)
}

func GenerateRefreshToken() (string, error) {
	buf := make([]byte, 48)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func HashRefreshToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}
