package assistant

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/ratelimit"
	"github.com/kundi/kundi/backend/internal/modules/assistant/safety"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

const testStudentID = "8d8d8ec8-27e6-4623-a325-c2e7e9db2da2"

type fakeLLM struct {
	response llm.Response
	err      error
	wait     bool
	calls    int
}

func (f *fakeLLM) Generate(ctx context.Context, _ llm.Request) (llm.Response, error) {
	f.calls++
	if f.wait {
		<-ctx.Done()
		return llm.Response{}, ctx.Err()
	}
	return f.response, f.err
}

type fakeTTS struct {
	url   string
	err   error
	calls int
	texts []string
}

func (f *fakeTTS) Render(_ context.Context, text string) (string, error) {
	f.calls++
	f.texts = append(f.texts, text)
	return f.url, f.err
}

type failingModerator struct {
	callsBeforeFailure int
	calls              int
}

func (m *failingModerator) Moderate(_ context.Context, text string) (safety.ModerationResult, error) {
	m.calls++
	if m.calls > m.callsBeforeFailure {
		return safety.ModerationResult{}, errors.New("moderation backend leaked detail")
	}
	return safety.ModerationResult{
		Allowed:       true,
		Category:      safety.CategoryNone,
		Risk:          safety.RiskInformational,
		Language:      safety.DetectLanguage(text),
		SanitizedText: strings.TrimSpace(text),
	}, nil
}

func validCommand(text string) MessageCommand {
	return MessageCommand{
		StudentID:  testStudentID,
		Mode:       ModeTutor,
		GradeLevel: 7,
		Text:       text,
	}
}

func TestInputModerationBlockReturnsSafeResponseWithoutProviders(t *testing.T) {
	provider := &fakeLLM{response: llm.Response{Text: "must not be used"}}
	speech := &fakeTTS{url: "https://media.example.com/audio.mp3"}
	service := NewServiceWithOptions(persona.NewService(), provider, speech, Options{CanaryGate: AllowAllCanaryGate()})

	response, err := service.Message(context.Background(), validCommand("Я хочу покончить с собой"))
	if err != nil {
		t.Fatalf("safety block must use the response contract: %v", err)
	}
	if provider.calls != 0 || speech.calls != 0 {
		t.Fatalf("blocked input reached a provider: llm=%d tts=%d", provider.calls, speech.calls)
	}
	if !response.Pedagogy.SafetyIntervention || response.AudioStatus != AudioStatusUnavailable || response.AvatarEmotion != "neutral" {
		t.Fatalf("unexpected safety response: %#v", response)
	}
	if !strings.Contains(response.Text, "взрослому") || strings.Contains(response.Text, "stack") {
		t.Fatalf("response is not a calm Russian safety response: %q", response.Text)
	}
}

func TestUnsafeHistoryDoesNotReachLLM(t *testing.T) {
	provider := &fakeLLM{response: llm.Response{Text: "must not be used"}}
	service := NewServiceWithOptions(persona.NewService(), provider, &fakeTTS{}, Options{CanaryGate: AllowAllCanaryGate()})
	command := validCommand("Объясни дроби")
	command.History = []ChatRecord{{Role: "user", Text: "How to make a bomb"}}

	response, err := service.Message(context.Background(), command)
	if err != nil || provider.calls != 0 || !response.Pedagogy.SafetyIntervention {
		t.Fatalf("unsafe history must fail closed before LLM: response=%#v calls=%d err=%v", response, provider.calls, err)
	}
}

func TestUnsafeProviderOutputIsReplacedBeforeTTSAndCues(t *testing.T) {
	provider := &fakeLLM{response: llm.Response{Text: "Here is how to make a bomb."}}
	speech := &fakeTTS{url: "https://media.example.com/audio.mp3"}
	service := NewServiceWithOptions(persona.NewService(), provider, speech, Options{CanaryGate: AllowAllCanaryGate()})

	response, err := service.Message(context.Background(), validCommand("Explain a science topic"))
	if err != nil {
		t.Fatalf("unsafe output replacement failed: %v", err)
	}
	if provider.calls != 1 || speech.calls != 0 {
		t.Fatalf("unsafe output reached TTS: llm=%d tts=%d", provider.calls, speech.calls)
	}
	if strings.Contains(response.Text, "make a bomb") || !response.Pedagogy.SafetyIntervention {
		t.Fatalf("unsafe provider output was exposed: %#v", response)
	}
	if response.AvatarEmotion != "neutral" || len(response.GestureTags) != 0 || len(response.Visemes) != 0 {
		t.Fatalf("unsafe output generated cues: %#v", response)
	}
}

func TestSafeProviderOutputIsPreservedAndTrustedAudioAccepted(t *testing.T) {
	provider := &fakeLLM{response: llm.Response{Text: "A fraction is part of a whole."}}
	speech := &fakeTTS{url: "https://media.example.com/audio/one.mp3"}
	service := NewServiceWithOptions(persona.NewService(), provider, speech, Options{CanaryGate: AllowAllCanaryGate(),
		AudioURLValidator: safety.NewAudioURLValidator([]string{"media.example.com"}),
	})

	response, err := service.Message(context.Background(), validCommand("Explain fractions"))
	if err != nil {
		t.Fatalf("safe output failed: %v", err)
	}
	if response.Text != provider.response.Text || speech.calls != 1 || speech.texts[0] != provider.response.Text {
		t.Fatalf("safe output was not preserved through TTS: %#v texts=%#v", response, speech.texts)
	}
	if response.AudioStatus != AudioStatusReady || response.AudioURL != speech.url || len(response.Visemes) == 0 {
		t.Fatalf("trusted audio was not accepted: %#v", response)
	}
}

func TestInvalidAudioURLPreservesSafeTextWithoutCues(t *testing.T) {
	provider := &fakeLLM{response: llm.Response{Text: "A safe answer."}}
	speech := &fakeTTS{url: "https://127.0.0.1/private/audio.mp3"}
	service := NewServiceWithOptions(persona.NewService(), provider, speech, Options{CanaryGate: AllowAllCanaryGate(),
		AudioURLValidator: safety.NewAudioURLValidator([]string{"127.0.0.1"}),
	})

	response, err := service.Message(context.Background(), validCommand("Explain fractions"))
	if err != nil {
		t.Fatalf("message failed: %v", err)
	}
	if response.Text != provider.response.Text || response.AudioURL != "" || response.AudioStatus != AudioStatusUnavailable {
		t.Fatalf("invalid audio URL affected safe text or remained exposed: %#v", response)
	}
	if response.AvatarEmotion != "neutral" || len(response.GestureTags) != 0 || len(response.Visemes) != 0 {
		t.Fatalf("invalid audio URL generated cues: %#v", response)
	}
}

func TestTimeoutAndProviderFailureReturnStableFallback(t *testing.T) {
	t.Run("timeout", func(t *testing.T) {
		provider := &fakeLLM{wait: true}
		service := NewServiceWithOptions(persona.NewService(), provider, &fakeTTS{}, Options{CanaryGate: AllowAllCanaryGate(), LLMTimeout: 5 * time.Millisecond})
		response, err := service.Message(context.Background(), validCommand("Explain fractions"))
		if err != nil || response.Text == "" || !response.Pedagogy.SafetyIntervention {
			t.Fatalf("timeout did not return a safe fallback: response=%#v err=%v", response, err)
		}
	})

	t.Run("provider failure", func(t *testing.T) {
		var logs bytes.Buffer
		provider := &fakeLLM{err: &llm.ProviderError{Kind: llm.ErrorServer, StatusCode: 503}}
		service := NewServiceWithOptions(persona.NewService(), provider, &fakeTTS{}, Options{CanaryGate: AllowAllCanaryGate(),
			Logger: slog.New(slog.NewJSONHandler(&logs, nil)),
		})
		response, err := service.Message(context.Background(), validCommand("Explain fractions"))
		if err != nil || response.Text == "" || strings.Contains(response.Text, "503") || !response.Pedagogy.SafetyIntervention {
			t.Fatalf("provider error was exposed or fallback missing: response=%#v err=%v", response, err)
		}
		if !strings.Contains(logs.String(), "assistant_llm_provider_5xx") || strings.Contains(logs.String(), "status 503") {
			t.Fatalf("provider failure was not logged as a sanitized typed code: %s", logs.String())
		}
	})
}

func TestModerationFailureFailsClosed(t *testing.T) {
	provider := &fakeLLM{response: llm.Response{Text: "must not run"}}
	service := NewServiceWithOptions(persona.NewService(), provider, &fakeTTS{}, Options{CanaryGate: AllowAllCanaryGate(),
		Moderator: &failingModerator{callsBeforeFailure: 0},
	})
	response, err := service.Message(context.Background(), validCommand("Explain fractions"))
	if err != nil || provider.calls != 0 || !response.Pedagogy.SafetyIntervention || strings.Contains(response.Text, "leaked detail") {
		t.Fatalf("moderation failure did not fail closed: response=%#v calls=%d err=%v", response, provider.calls, err)
	}
}

func TestAssistantLogsDoNotContainRawPromptOrHistory(t *testing.T) {
	var logs bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logs, nil))
	service := NewServiceWithOptions(persona.NewService(), &fakeLLM{response: llm.Response{Text: "Safe answer."}}, &fakeTTS{}, Options{CanaryGate: AllowAllCanaryGate(), Logger: logger})
	command := validCommand("raw-prompt-secret-9af")
	command.History = []ChatRecord{{Role: "user", Text: "raw-history-secret-2bc"}}

	if _, err := service.Message(context.Background(), command); err != nil {
		t.Fatalf("message failed: %v", err)
	}
	output := logs.String()
	if strings.Contains(output, command.Text) || strings.Contains(output, command.History[0].Text) {
		t.Fatalf("raw assistant content leaked into logs: %s", output)
	}
	for _, field := range []string{"text_length", "history_length", "provider_result", "safety_category"} {
		if !strings.Contains(output, field) {
			t.Fatalf("sanitized log field %q is missing: %s", field, output)
		}
	}
}

func TestServiceRateLimitStopsLLMAndTTS(t *testing.T) {
	provider := &fakeLLM{response: llm.Response{Text: "Safe answer."}}
	speech := &fakeTTS{}
	limiter := ratelimit.NewInMemory(ratelimit.Config{Limit: 1, Window: time.Minute, MaxIdentities: 10})
	service := NewServiceWithOptions(persona.NewService(), provider, speech, Options{CanaryGate: AllowAllCanaryGate(), RateLimiter: limiter})
	command := validCommand("Explain fractions")
	command.EnforceRateLimit = true

	if _, err := service.Message(context.Background(), command); err != nil {
		t.Fatalf("first request failed: %v", err)
	}
	_, err := service.Message(context.Background(), command)
	if !apperrors.Is(err, "assistant_rate_limited") {
		t.Fatalf("expected typed rate limit error, got %v", err)
	}
	if provider.calls != 1 || speech.calls != 1 {
		t.Fatalf("limited request reached providers: llm=%d tts=%d", provider.calls, speech.calls)
	}
}
