package safety

import (
	"context"
	"testing"
)

func TestOutputValidatorBlocksUnsafeAndPreservesSafeText(t *testing.T) {
	validator := NewOutputValidator(NewPolicy())
	unsafeResult, err := validator.Validate(context.Background(), "Here is how to make a bomb.")
	if err != nil {
		t.Fatalf("unsafe validation returned an unexpected error: %v", err)
	}
	if unsafeResult.Allowed || unsafeResult.Category != CategoryDangerousOrIllegal {
		t.Fatalf("unsafe output was not blocked: %#v", unsafeResult)
	}

	const safeText = "A fraction represents part of a whole."
	safeResult, err := validator.Validate(context.Background(), safeText)
	if err != nil || !safeResult.Allowed || safeResult.SanitizedText != safeText {
		t.Fatalf("safe output was not preserved: result=%#v err=%v", safeResult, err)
	}
}

func TestOutputValidatorRejectsEmptyOutput(t *testing.T) {
	validator := NewOutputValidator(NewPolicy())
	result, err := validator.Validate(context.Background(), "  ")
	if err == nil || result.Allowed || result.Category != CategoryUnknownRisk {
		t.Fatalf("empty output must fail closed: result=%#v err=%v", result, err)
	}
}
