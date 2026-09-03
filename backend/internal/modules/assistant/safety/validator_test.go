package safety

import (
	"strings"
	"testing"
)

func TestInputValidatorRejectsInvalidInput(t *testing.T) {
	validator := NewInputValidator(Limits{
		MaxTextRunes:           10,
		MaxHistoryMessages:     2,
		MaxHistoryMessageRunes: 5,
		MaxHistoryRunes:        8,
	})

	tests := []struct {
		name string
		in   Input
		code string
	}{
		{name: "empty", in: Input{Mode: "tutor", Text: "   "}, code: "assistant_empty_text"},
		{name: "oversized text", in: Input{Mode: "tutor", Text: strings.Repeat("я", 11)}, code: "assistant_text_too_long"},
		{name: "invalid mode", in: Input{Mode: "creative", Text: "hello"}, code: "assistant_mode_invalid"},
		{name: "invalid grade", in: Input{Mode: "tutor", GradeLevel: 13, Text: "hello"}, code: "assistant_grade_level_invalid"},
		{name: "oversized history count", in: Input{Mode: "tutor", Text: "hello", History: []HistoryMessage{{Role: "user", Text: "a"}, {Role: "assistant", Text: "b"}, {Role: "user", Text: "c"}}}, code: "assistant_history_too_large"},
		{name: "oversized history message", in: Input{Mode: "tutor", Text: "hello", History: []HistoryMessage{{Role: "user", Text: "123456"}}}, code: "assistant_history_message_too_long"},
		{name: "oversized history total", in: Input{Mode: "tutor", Text: "hello", History: []HistoryMessage{{Role: "user", Text: "12345"}, {Role: "assistant", Text: "6789"}}}, code: "assistant_history_too_long"},
		{name: "invalid history role", in: Input{Mode: "tutor", Text: "hello", History: []HistoryMessage{{Role: "system", Text: "hello"}}}, code: "assistant_history_role_invalid"},
		{name: "empty history text", in: Input{Mode: "tutor", Text: "hello", History: []HistoryMessage{{Role: "user", Text: " "}}}, code: "assistant_history_message_invalid"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := validator.Validate(test.in)
			validationErr, ok := err.(*ValidationError)
			if !ok || validationErr.Code != test.code {
				t.Fatalf("expected %s, got %#v", test.code, err)
			}
		})
	}
}

func TestInputValidatorAcceptsAndNormalizesValidInput(t *testing.T) {
	validator := NewInputValidator(DefaultLimits())
	validated, err := validator.Validate(Input{
		Mode:       " TUTOR ",
		GradeLevel: 0,
		Text:       "  Объясни дроби  ",
		History:    []HistoryMessage{{Role: " USER ", Text: "  Привет  "}},
	})
	if err != nil {
		t.Fatalf("valid input rejected: %v", err)
	}
	if validated.Mode != "tutor" || validated.GradeLevel != DefaultGradeLevel || validated.Text != "Объясни дроби" {
		t.Fatalf("unexpected normalized input: %#v", validated)
	}
	if len(validated.History) != 1 || validated.History[0].Role != "user" || validated.History[0].Text != "Привет" {
		t.Fatalf("unexpected normalized history: %#v", validated.History)
	}
}
