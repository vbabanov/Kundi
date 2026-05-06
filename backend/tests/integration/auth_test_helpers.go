package integration

import (
	"testing"
	"time"

	"github.com/google/uuid"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
)

func issueAccessToken(t *testing.T, tokens *platformauth.AccessTokenService, studentID uuid.UUID) string {
	t.Helper()
	token, _, err := tokens.Issue(studentID, time.Now().UTC())
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}
	return token
}
