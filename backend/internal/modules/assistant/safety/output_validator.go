package safety

import (
	"context"
	"errors"
	"strings"
)

var ErrEmptyOutput = errors.New("assistant output is empty")

type OutputValidator struct {
	moderator Moderator
}

func NewOutputValidator(moderator Moderator) *OutputValidator {
	if moderator == nil {
		moderator = NewPolicy()
	}
	return &OutputValidator{moderator: moderator}
}

func (v *OutputValidator) Validate(ctx context.Context, text string) (ModerationResult, error) {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return ModerationResult{
			Allowed:       false,
			Category:      CategoryUnknownRisk,
			Risk:          RiskHarmful,
			Language:      LanguageEnglish,
			ReasonCode:    "empty_output",
			SanitizedText: "",
		}, ErrEmptyOutput
	}
	return v.moderator.Moderate(ctx, trimmed)
}
