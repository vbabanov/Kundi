package assistant

import (
	"context"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/speechauth"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

type speechRepo struct {
	*memorySessionRepository
	message   SessionMessage
	inputMode string
	deleted   bool
}

func (r *speechRepo) SpeechMessage(_ context.Context, student, session, message uuid.UUID) (SessionMessage, string, error) {
	if r.deleted || student != r.owner || session.String() != r.session.ID || message.String() != r.message.ID {
		return SessionMessage{}, "", ErrSessionNotFound
	}
	return r.message, r.inputMode, nil
}
func TestSpeechAuthorizationOwnershipAndContent(t *testing.T) {
	for _, name := range []string{"valid", "student", "session", "message", "role", "typed", "deleted", "empty", "long", "off", "voice_off"} {
		t.Run(name, func(t *testing.T) {
			student, session, message := uuid.New(), uuid.New(), uuid.New()
			repo := &speechRepo{memorySessionRepository: newMemorySessionRepository(student, session, 7),
				message: SessionMessage{ID: message.String(), SessionID: session.String(), Role: "assistant", Content: "Подсказка."}, inputMode: "voice"}
			enabled, voice := true, true
			ttsEnabled := true
			switch name {
			case "student":
				student = uuid.New()
			case "session":
				session = uuid.New()
			case "message":
				message = uuid.New()
			case "role":
				repo.message.Role = "user"
			case "typed":
				repo.inputMode = "text"
			case "deleted":
				repo.deleted = true
			case "empty":
				repo.message.Content = " "
			case "long":
				repo.message.Content = strings.Repeat("а", MaxSpeechMessageRunes+1)
			case "off":
				ttsEnabled = false
			case "voice_off":
				voice = false
			}
			service := NewServiceWithOptions(nil, nil, nil, Options{Enabled: &enabled, VoiceInputEnabled: &voice,
				SessionRepository: repo, SpeechBroker: speechauth.New(speechauth.Config{Enabled: ttsEnabled})})
			_, err := service.SpeechAuthorization(context.Background(), student.String(), session.String(), message.String())
			want := "assistant_message_not_found"
			switch name {
			case "valid":
				want = "speech_configuration"
			case "empty", "long":
				want = "speech_content_invalid"
			case "off", "voice_off":
				want = "assistant_tts_disabled"
			}
			if !apperrors.Is(err, want) {
				t.Fatalf("got %v want %s", err, want)
			}
			if len(repo.exchanges) != 0 {
				t.Fatal("authorization persisted data")
			}
		})
	}
}
