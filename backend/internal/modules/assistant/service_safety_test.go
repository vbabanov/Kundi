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
	"github.com/kundi/kundi/backend/internal/platform/observability"
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
		return f.response, ctx.Err()
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
		provider := &fakeLLM{err: &llm.ProviderError{Kind: llm.ErrorServer, StatusCode: 503}}
		metrics := &capturingMetrics{}
		service := NewServiceWithOptions(persona.NewService(), provider, &fakeTTS{}, Options{CanaryGate: AllowAllCanaryGate(),
			Observe: observability.Hooks{Metrics: metrics},
		})
		response, err := service.Message(context.Background(), validCommand("Explain fractions"))
		if err != nil || response.Text == "" || strings.Contains(response.Text, "503") || !response.Pedagogy.SafetyIntervention {
			t.Fatalf("provider error was exposed or fallback missing: response=%#v err=%v", response, err)
		}
		assertOneAssistantOutcome(t, metrics, OutcomeProvider5xx)
	})
}

func TestIncompleteProviderContentIsNotReturnedOrSentToTTS(t *testing.T) {
	const partial = "PARTIAL_PROVIDER_CONTENT_MUST_BE_DISCARDED"
	provider := &fakeLLM{
		response: llm.Response{
			Text: partial, Provider: "alem", Model: "gemma4", Stage: llm.StagePrimary,
			FinishReason: llm.FinishReasonLength,
		},
		err: &llm.ProviderError{Kind: llm.ErrorIncomplete},
	}
	speech := &fakeTTS{}
	service := NewServiceWithOptions(persona.NewService(), provider, speech, Options{CanaryGate: AllowAllCanaryGate()})
	response, err := service.Message(context.Background(), validCommand("Explain fractions"))
	if err != nil || response.Text == "" || strings.Contains(response.Text, partial) {
		t.Fatalf("incomplete content escaped into response: response=%#v err=%v", response, err)
	}
	if len(speech.texts) != 1 || strings.Contains(speech.texts[0], partial) {
		t.Fatalf("incomplete content escaped into TTS: %#v", speech.texts)
	}
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

func TestAssistantMetricLogsDoNotContainPIIOrRawContent(t *testing.T) {
	var logs bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logs, nil))
	hooks := observability.New(observability.Config{Mode: "log"}, logger)
	responseValue := "Safe response marker 7C1"
	authorizationValue := "AUTHVAL_5E8"
	tokenValue := "TOKVAL_8B2"
	secretValue := "SECVAL_3D4"
	service := NewServiceWithOptions(persona.NewService(), &fakeLLM{response: llm.Response{Text: responseValue, Provider: "alem", Model: "gemma4"}}, &fakeTTS{}, Options{CanaryGate: AllowAllCanaryGate(), Logger: logger, Observe: hooks})
	command := validCommand("Explain fractions marker 9AF")
	command.History = []ChatRecord{{Role: "user", Text: "Prior lesson marker 2BC " + authorizationValue + " " + tokenValue + " " + secretValue}}

	if _, err := service.Message(context.Background(), command); err != nil {
		t.Fatalf("message failed: %v", err)
	}
	output := logs.String()
	for _, forbiddenValue := range []string{command.Text, command.History[0].Text, command.StudentID, responseValue, authorizationValue, tokenValue, secretValue} {
		if strings.Contains(output, forbiddenValue) {
			t.Fatalf("raw assistant value %q leaked into logs: %s", forbiddenValue, output)
		}
	}
	for _, field := range []string{"assistant_requests_total", "assistant_latency_ms", "safety_category"} {
		if !strings.Contains(output, field) {
			t.Fatalf("sanitized log field %q is missing: %s", field, output)
		}
	}
	for _, forbiddenField := range []string{"student_id", "session_id", "account_id", "prompt", "response", "history", "transcript", "token", "authorization", "endpoint"} {
		if strings.Contains(strings.ToLower(output), forbiddenField) {
			t.Fatalf("forbidden telemetry field %q is present: %s", forbiddenField, output)
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
