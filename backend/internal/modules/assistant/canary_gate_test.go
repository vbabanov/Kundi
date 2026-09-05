package assistant

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

func TestCanaryGateFailClosedAndAllowlist(t *testing.T) {
	allowed := uuid.New()
	denied := uuid.New()

	var nilGate *CanaryGate
	if nilGate.Allows(allowed) {
		t.Fatal("nil gate must deny")
	}
	if (&CanaryGate{}).Allows(allowed) {
		t.Fatal("zero-value gate must deny")
	}
	if _, err := NewCanaryGate(RolloutModeAllowlist, nil); err == nil {
		t.Fatal("empty allowlist must be rejected")
	}
	if _, err := NewCanaryGate("percentage", []uuid.UUID{allowed}); err == nil {
		t.Fatal("invalid rollout mode must be rejected")
	}
	gate, err := NewCanaryGate(RolloutModeAllowlist, []uuid.UUID{allowed, allowed})
	if err != nil {
		t.Fatalf("new gate: %v", err)
	}
	if !gate.Allows(allowed) || gate.Allows(denied) {
		t.Fatal("allowlist gate returned an incorrect cohort decision")
	}
	if len(gate.allowed) != 1 {
		t.Fatalf("duplicate UUIDs were not deduplicated: %d", len(gate.allowed))
	}
}

func TestServiceWithUnconfiguredGateFailsClosedBeforeProvider(t *testing.T) {
	provider := &fakeLLM{response: llm.Response{Text: "must not be called"}}
	enabled := true
	service := NewServiceWithOptions(nil, provider, nil, Options{Enabled: &enabled})
	_, err := service.Message(context.Background(), MessageCommand{
		StudentID: uuid.NewString(), Mode: ModeTutor, GradeLevel: 7, Text: "synthetic",
	})
	if !apperrors.Is(err, "assistant_unavailable") || provider.calls != 0 {
		t.Fatalf("unconfigured gate did not fail closed: err=%v calls=%d", err, provider.calls)
	}
}

func TestCanaryGateExplicitAll(t *testing.T) {
	gate, err := NewCanaryGate(RolloutModeAll, nil)
	if err != nil || !gate.Allows(uuid.New()) {
		t.Fatalf("explicit all gate must allow: err=%v", err)
	}
}
