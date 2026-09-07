package unit

import (
	"context"
	"testing"

	assistant "github.com/kundi/kundi/backend/internal/modules/assistant"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tts"
	"github.com/kundi/kundi/backend/internal/modules/persona"
)

func TestAssistantModeRoutingAndGradeBand(t *testing.T) {
	svc := assistant.NewServiceWithOptions(
		persona.NewService(),
		llm.NewDeterministicProvider(),
		tts.NewService(""),
		assistant.Options{CanaryGate: assistant.AllowAllCanaryGate()},
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
	if tutor.Behavior.GradeBand != "3-4" {
		t.Fatalf("expected 3-4 grade band, got %s", tutor.Behavior.GradeBand)
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
	if general.Behavior.GradeBand != "10-11" {
		t.Fatalf("expected 10-11 grade band, got %s", general.Behavior.GradeBand)
	}
	if general.Pedagogy.NeedsScaffold {
		t.Fatalf("general mode should not force scaffold")
	}
}

func TestAssistantModerationRestriction(t *testing.T) {
	svc := assistant.NewServiceWithOptions(
		persona.NewService(),
		llm.NewDeterministicProvider(),
		tts.NewService(""),
		assistant.Options{CanaryGate: assistant.AllowAllCanaryGate()},
	)

	response, err := svc.Message(context.Background(), assistant.MessageCommand{
		StudentID: "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
		Mode:      assistant.ModeTutor,
		Text:      "I want to kill myself",
	})
	if err != nil {
		t.Fatalf("moderation block must use the assistant response contract: %v", err)
	}
	if !response.Pedagogy.SafetyIntervention || response.AudioStatus != assistant.AudioStatusUnavailable {
		t.Fatalf("expected a safe intervention response, got %#v", response)
	}
}
