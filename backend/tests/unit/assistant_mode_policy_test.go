package unit

import (
	"context"
	"testing"

	assistant "github.com/kundi/kundi/backend/internal/modules/assistant"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tts"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

func TestAssistantModeRoutingAndGradeBand(t *testing.T) {
	svc := assistant.NewService(
		persona.NewService(),
		llm.NewDeterministicProvider(),
		tts.NewService(""),
	)

	tutor, err := svc.Message(context.Background(), assistant.MessageCommand{
		StudentID:  "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		Mode:       assistant.ModeTutor,
		GradeLevel: 3,
		Text:       "Help me solve this problem",
	})
	if err != nil {
		t.Fatalf("tutor mode failed: %v", err)
	}
	if tutor.Behavior.Mode != "tutor" {
		t.Fatalf("expected tutor mode, got %s", tutor.Behavior.Mode)
	}
	if tutor.Behavior.GradeBand != "primary" {
		t.Fatalf("expected primary grade band, got %s", tutor.Behavior.GradeBand)
	}
	if !tutor.Pedagogy.NeedsScaffold {
		t.Fatalf("tutor mode must include scaffold")
	}

	general, err := svc.Message(context.Background(), assistant.MessageCommand{
		StudentID:  "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		Mode:       assistant.ModeGeneralChat,
		GradeLevel: 10,
		Text:       "How is your day?",
	})
	if err != nil {
		t.Fatalf("general mode failed: %v", err)
	}
	if general.Behavior.Mode != "general_chat" {
		t.Fatalf("expected general_chat mode, got %s", general.Behavior.Mode)
	}
	if general.Behavior.GradeBand != "senior" {
		t.Fatalf("expected senior grade band, got %s", general.Behavior.GradeBand)
	}
	if general.Pedagogy.NeedsScaffold {
		t.Fatalf("general mode should not force scaffold")
	}
}

func TestAssistantModerationRestriction(t *testing.T) {
	svc := assistant.NewService(
		persona.NewService(),
		llm.NewDeterministicProvider(),
		tts.NewService(""),
	)

	_, err := svc.Message(context.Background(), assistant.MessageCommand{
		StudentID: "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		Mode:      assistant.ModeTutor,
		Text:      "I want to kill yourself",
	})
	if err == nil {
		t.Fatalf("expected moderation block error")
	}
	if !apperrors.Is(err, "assistant_moderation_blocked") {
		t.Fatalf("expected assistant_moderation_blocked, got %v", err)
	}
}
