package aihandlers

import (
	"context"
	"testing"

	"github.com/google/uuid"
	assistantmodule "github.com/kundi/kundi/backend/internal/modules/assistant"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/jobs"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

type fakeAssistant struct {
	called bool
}

type countingProvider struct{ calls int }

func (p *countingProvider) Generate(context.Context, llm.Request) (llm.Response, error) {
	p.calls++
	return llm.Response{Text: "must not be called"}, nil
}

func TestAIPostProcessingInheritsAssistantCanaryGate(t *testing.T) {
	allowed := uuid.New()
	denied := uuid.New()
	gate, err := assistantmodule.NewCanaryGate(assistantmodule.RolloutModeAllowlist, []uuid.UUID{allowed})
	if err != nil {
		t.Fatal(err)
	}
	provider := &countingProvider{}
	enabled := true
	service := assistantmodule.NewServiceWithOptions(persona.NewService(), provider, nil, assistantmodule.Options{Enabled: &enabled, CanaryGate: gate})
	audit := &fakeAudit{}
	worker := NewWorker(service, audit)

	err = worker.AIPostProcessing(context.Background(), jobs.Job{ID: "denied-job", Payload: map[string]any{
		"student_id": denied.String(), "text": "synthetic", "mode": "tutor", "grade_level": 7,
	}})
	if !apperrors.Is(err, "assistant_unavailable") {
		t.Fatalf("worker did not inherit canary denial: %v", err)
	}
	if provider.calls != 0 || audit.called {
		t.Fatalf("denied worker job reached dependencies: provider=%d audit=%v", provider.calls, audit.called)
	}
}

func (f *fakeAssistant) Message(_ context.Context, _ assistantmodule.MessageCommand) (assistantmodule.Response, error) {
	f.called = true
	return assistantmodule.Response{Text: "ok"}, nil
}

type fakeAudit struct {
	called bool
}

func (f *fakeAudit) Log(_ context.Context, _ string, _ string, _ string, _ string, _ map[string]any) error {
	f.called = true
	return nil
}

func TestAIPostProcessingHandler(t *testing.T) {
	assistant := &fakeAssistant{}
	audit := &fakeAudit{}
	worker := NewWorker(assistant, audit)

	err := worker.AIPostProcessing(context.Background(), jobs.Job{
		ID: "ai-job-1",
		Payload: map[string]any{
			"student_id":  "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2",
			"text":        "Explain fractions",
			"mode":        "tutor",
			"grade_level": 6,
		},
	})
	if err != nil {
		t.Fatalf("handler failed: %v", err)
	}
	if !assistant.called {
		t.Fatalf("assistant service should be called")
	}
	if !audit.called {
		t.Fatalf("audit service should be called")
	}
}
