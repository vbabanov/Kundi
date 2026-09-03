package safety

import (
	"strings"
	"unicode/utf8"
)

const (
	DefaultMaxRequestBodyBytes    int64 = 64 * 1024
	DefaultMaxTextRunes                 = 4_000
	DefaultMaxHistoryMessages           = 20
	DefaultMaxHistoryMessageRunes       = 4_000
	DefaultMaxHistoryRunes              = 12_000
	DefaultGradeLevel                   = 7
	MinimumGradeLevel                   = 1
	MaximumGradeLevel                   = 12
)

type Limits struct {
	MaxTextRunes           int
	MaxHistoryMessages     int
	MaxHistoryMessageRunes int
	MaxHistoryRunes        int
}

func DefaultLimits() Limits {
	return Limits{
		MaxTextRunes:           DefaultMaxTextRunes,
		MaxHistoryMessages:     DefaultMaxHistoryMessages,
		MaxHistoryMessageRunes: DefaultMaxHistoryMessageRunes,
		MaxHistoryRunes:        DefaultMaxHistoryRunes,
	}
}

type InputValidator struct {
	limits Limits
}

func NewInputValidator(limits Limits) *InputValidator {
	defaults := DefaultLimits()
	if limits.MaxTextRunes <= 0 {
		limits.MaxTextRunes = defaults.MaxTextRunes
	}
	if limits.MaxHistoryMessages <= 0 {
		limits.MaxHistoryMessages = defaults.MaxHistoryMessages
	}
	if limits.MaxHistoryMessageRunes <= 0 {
		limits.MaxHistoryMessageRunes = defaults.MaxHistoryMessageRunes
	}
	if limits.MaxHistoryRunes <= 0 {
		limits.MaxHistoryRunes = defaults.MaxHistoryRunes
	}
	return &InputValidator{limits: limits}
}

func (v *InputValidator) Validate(input Input) (ValidatedInput, error) {
	text := strings.TrimSpace(input.Text)
	if text == "" {
		return ValidatedInput{}, validationError("assistant_empty_text", "assistant text is required")
	}
	if !utf8.ValidString(text) {
		return ValidatedInput{}, validationError("assistant_text_invalid", "assistant text must be valid UTF-8")
	}
	if utf8.RuneCountInString(text) > v.limits.MaxTextRunes {
		return ValidatedInput{}, validationErrorf("assistant_text_too_long", "assistant text exceeds %d characters", v.limits.MaxTextRunes)
	}

	mode := strings.ToLower(strings.TrimSpace(input.Mode))
	if mode != "tutor" && mode != "general_chat" {
		return ValidatedInput{}, validationError("assistant_mode_invalid", "assistant mode must be tutor or general_chat")
	}

	gradeLevel := input.GradeLevel
	if gradeLevel == 0 {
		gradeLevel = DefaultGradeLevel
	}
	if gradeLevel < MinimumGradeLevel || gradeLevel > MaximumGradeLevel {
		return ValidatedInput{}, validationErrorf("assistant_grade_level_invalid", "grade_level must be between %d and %d", MinimumGradeLevel, MaximumGradeLevel)
	}

	if len(input.History) > v.limits.MaxHistoryMessages {
		return ValidatedInput{}, validationErrorf("assistant_history_too_large", "assistant history exceeds %d messages", v.limits.MaxHistoryMessages)
	}

	history := make([]HistoryMessage, 0, len(input.History))
	totalRunes := 0
	for index, message := range input.History {
		role := cleanRole(message.Role)
		if role != "user" && role != "assistant" {
			return ValidatedInput{}, validationErrorf("assistant_history_role_invalid", "history message %d has an invalid role", index)
		}
		messageText := strings.TrimSpace(message.Text)
		if messageText == "" || !utf8.ValidString(messageText) {
			return ValidatedInput{}, validationErrorf("assistant_history_message_invalid", "history message %d has invalid text", index)
		}
		messageRunes := utf8.RuneCountInString(messageText)
		if messageRunes > v.limits.MaxHistoryMessageRunes {
			return ValidatedInput{}, validationErrorf("assistant_history_message_too_long", "history message %d exceeds %d characters", index, v.limits.MaxHistoryMessageRunes)
		}
		totalRunes += messageRunes
		if totalRunes > v.limits.MaxHistoryRunes {
			return ValidatedInput{}, validationErrorf("assistant_history_too_long", "assistant history exceeds %d total characters", v.limits.MaxHistoryRunes)
		}
		history = append(history, HistoryMessage{Role: role, Text: messageText})
	}

	return ValidatedInput{
		Mode:       mode,
		GradeLevel: gradeLevel,
		Text:       text,
		History:    history,
	}, nil
}
