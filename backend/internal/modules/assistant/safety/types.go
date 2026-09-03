package safety

import (
	"context"
	"fmt"
	"strings"
)

type SafetyCategory string

const (
	CategoryNone               SafetyCategory = "none"
	CategorySelfHarm           SafetyCategory = "self_harm"
	CategoryViolenceOrAbuse    SafetyCategory = "violence_or_abuse"
	CategoryBullying           SafetyCategory = "bullying"
	CategorySexualSafety       SafetyCategory = "sexual_safety"
	CategoryDangerousOrIllegal SafetyCategory = "dangerous_or_illegal"
	CategoryMedicalHighStakes  SafetyCategory = "medical_high_stakes"
	CategoryPrivacyOrSecrets   SafetyCategory = "privacy_or_secrets"
	CategoryHarassment         SafetyCategory = "harassment"
	CategoryUnknownRisk        SafetyCategory = "unknown_risk"
)

type RiskLevel string

const (
	RiskInformational RiskLevel = "informational_or_educational"
	RiskHarmful       RiskLevel = "harmful_or_actionable"
	RiskImmediate     RiskLevel = "immediate_safety_concern"
)

type Language string

const (
	LanguageEnglish Language = "en"
	LanguageRussian Language = "ru"
	LanguageKazakh  Language = "kk"
)

type ModerationResult struct {
	Allowed       bool
	Category      SafetyCategory
	Risk          RiskLevel
	Language      Language
	ReasonCode    string
	SanitizedText string
}

type Moderator interface {
	Moderate(ctx context.Context, text string) (ModerationResult, error)
}

type HistoryMessage struct {
	Role string
	Text string
}

type Input struct {
	Mode       string
	GradeLevel int
	Text       string
	History    []HistoryMessage
}

type ValidatedInput struct {
	Mode       string
	GradeLevel int
	Text       string
	History    []HistoryMessage
}

type ValidationError struct {
	Code    string
	Message string
}

func (e *ValidationError) Error() string {
	if e == nil {
		return ""
	}
	return e.Message
}

func validationError(code, message string) error {
	return &ValidationError{Code: code, Message: message}
}

func validationErrorf(code, format string, args ...any) error {
	return validationError(code, fmt.Sprintf(format, args...))
}

func cleanRole(role string) string {
	return strings.ToLower(strings.TrimSpace(role))
}
