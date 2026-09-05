package assistant

import (
	"fmt"
	"strings"

	"github.com/google/uuid"
)

const (
	RolloutModeAllowlist = "allowlist"
	RolloutModeAll       = "all"
)

// CanaryGate is independent of transports and providers. Its zero value and a
// nil pointer both deny access so missing production wiring fails closed.
type CanaryGate struct {
	mode    string
	allowed map[uuid.UUID]struct{}
}

func NewCanaryGate(mode string, studentIDs []uuid.UUID) (*CanaryGate, error) {
	normalized := strings.ToLower(strings.TrimSpace(mode))
	if normalized == "" {
		normalized = RolloutModeAllowlist
	}
	switch normalized {
	case RolloutModeAll:
		return &CanaryGate{mode: RolloutModeAll}, nil
	case RolloutModeAllowlist:
		allowed := make(map[uuid.UUID]struct{}, len(studentIDs))
		for _, id := range studentIDs {
			if id == uuid.Nil {
				return nil, fmt.Errorf("assistant canary allowlist contains an invalid UUID")
			}
			allowed[id] = struct{}{}
		}
		if len(allowed) == 0 {
			return nil, fmt.Errorf("assistant canary allowlist is empty")
		}
		return &CanaryGate{mode: RolloutModeAllowlist, allowed: allowed}, nil
	default:
		return nil, fmt.Errorf("assistant rollout mode is invalid")
	}
}

// AllowAllCanaryGate is intentionally explicit for tests and controlled
// global rollouts. Production must only use it for rollout mode "all".
func AllowAllCanaryGate() *CanaryGate {
	return &CanaryGate{mode: RolloutModeAll}
}

func (g *CanaryGate) Allows(studentID uuid.UUID) bool {
	if g == nil || studentID == uuid.Nil {
		return false
	}
	if g.mode == RolloutModeAll {
		return true
	}
	if g.mode != RolloutModeAllowlist {
		return false
	}
	_, ok := g.allowed[studentID]
	return ok
}
