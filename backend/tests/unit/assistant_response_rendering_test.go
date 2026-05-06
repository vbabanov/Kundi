package unit

import (
	"context"
	"errors"
	"testing"

	assistant "github.com/kundi/kundi/backend/internal/modules/assistant"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tts"
	"github.com/kundi/kundi/backend/internal/modules/persona"
)

func TestAssistantRenderingContracts(t *testing.T) {
	svc := assistant.NewService(
		persona.NewService(),
		llm.NewDeterministicProvider(),
		tts.NewService(""),
	)

	tutor, err := svc.Message(context.Background(), assistant.MessageCommand{
		StudentID: "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		Mode:      assistant.ModeTutor,
		Text:      "Help me with equations",
	})
	if err != nil {
		t.Fatalf("tutor message failed: %v", err)
	}
	if tutor.Text == "" || tutor.AvatarEmotion == "" {
		t.Fatalf("assistant response must include text and emotion")
	}
	if tutor.AudioStatus != assistant.AudioStatusReady {
		t.Fatalf("expected ready audio status, got %s", tutor.AudioStatus)
	}
	if !tutor.Pedagogy.NeedsScaffold {
		t.Fatalf("tutor mode must request scaffold")
	}

	general, err := svc.Message(context.Background(), assistant.MessageCommand{
		StudentID: "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		Mode:      assistant.ModeGeneralChat,
		Text:      "How are you?",
	})
	if err != nil {
		t.Fatalf("general message failed: %v", err)
	}
	if general.Pedagogy.NeedsScaffold {
		t.Fatalf("general mode should not force scaffold")
	}
}

type failingTTS struct{}

func (failingTTS) Render(context.Context, string) (string, error) {
	return "", errors.New("tts unavailable")
}

func TestAssistantTTSFailureFallbackContract(t *testing.T) {
	svc := assistant.NewService(
		persona.NewService(),
		llm.NewDeterministicProvider(),
		failingTTS{},
	)

	resp, err := svc.Message(context.Background(), assistant.MessageCommand{
		StudentID: "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		Mode:      assistant.ModeTutor,
		Text:      "Explain fractions",
	})
	if err != nil {
		t.Fatalf("message failed: %v", err)
	}
	if resp.AudioStatus != assistant.AudioStatusUnavailable {
		t.Fatalf("expected unavailable audio status, got %s", resp.AudioStatus)
	}
	if resp.AudioURL != "" {
		t.Fatalf("audioUrl must be empty when tts is unavailable")
	}
	if len(resp.Visemes) != 0 {
		t.Fatalf("visemes must be empty when audio is unavailable")
	}
	if resp.AvatarEmotion != "neutral" {
		t.Fatalf("emotion must fallback to neutral when audio is unavailable")
	}
	if len(resp.GestureTags) != 0 {
		t.Fatalf("gesture tags must be empty when audio is unavailable")
	}
}
