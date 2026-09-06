package assistant

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/ratelimit"
	"github.com/kundi/kundi/backend/internal/modules/assistant/safety"
	"github.com/kundi/kundi/backend/internal/modules/assistant/speechauth"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tutoring"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
	"github.com/kundi/kundi/backend/internal/platform/observability"
)

type capturedMetric struct {
	Kind  string            `json:"kind"`
	Name  string            `json:"name"`
	Value float64           `json:"value,omitempty"`
	Tags  map[string]string `json:"tags"`
}

type capturingMetrics struct {
	mu    sync.Mutex
	calls []capturedMetric
}

func (m *capturingMetrics) Incr(name string, tags map[string]string) {
	m.capture(capturedMetric{Kind: "counter", Name: name, Tags: cloneTags(tags)})
}

func (m *capturingMetrics) Observe(name string, value float64, tags map[string]string) {
	m.capture(capturedMetric{Kind: "histogram", Name: name, Value: value, Tags: cloneTags(tags)})
}

func (m *capturingMetrics) capture(call capturedMetric) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.calls = append(m.calls, call)
}

func (m *capturingMetrics) named(name string) []capturedMetric {
	m.mu.Lock()
	defer m.mu.Unlock()
	items := make([]capturedMetric, 0)
	for _, call := range m.calls {
		if call.Name == name {
			items = append(items, call)
		}
	}
	return items
}

func cloneTags(tags map[string]string) map[string]string {
	copy := make(map[string]string, len(tags))
	for key, value := range tags {
		copy[key] = value
	}
	return copy
}

func TestAssistantOutcomeRecorderIsOnceOnly(t *testing.T) {
	metrics := &capturingMetrics{}
	recorder := newAssistantOutcome(metrics, OperationLegacyMessage, "legacy")
	recorder.SetResult(OutcomeSuccess, telemetryNone)
	recorder.Finish(nil)
	recorder.Finish(errors.New("must not emit a second outcome"))
	assertOneAssistantOutcome(t, metrics, OutcomeSuccess)
}

func TestGenerationOutcomeRecorderIsOnceOnlyOnCancellation(t *testing.T) {
	metrics := &capturingMetrics{}
	recorder := newAssistantGenerationOutcome(metrics, "kk-KZ", InputModeText)
	response := llm.Response{
		Provider: "alem", Model: "gemma4", Stage: llm.StagePrimary, FinishReason: llm.FinishReasonMissing,
		Attempts: []llm.Attempt{{Provider: "alem", Model: "gemma4", Stage: llm.StagePrimary, FinishReason: llm.FinishReasonMissing, LatencyMS: 1}},
	}
	recorder.Finish(response, context.Canceled)
	recorder.Finish(response, nil)
	assertOneGenerationOutcome(t, metrics, OutcomeInternalError)
}

func TestAssistantTerminalOutcomesEmitExactlyOnce(t *testing.T) {
	tests := []struct {
		name       string
		provider   *fakeLLM
		command    MessageCommand
		timeout    time.Duration
		limiter    ratelimit.Limiter
		wantResult string
		wantMetric string
		generation bool
	}{
		{name: "success", provider: &fakeLLM{response: generationTestResponse("Safe answer.", nil)}, command: validCommand("Explain fractions"), wantResult: OutcomeSuccess, generation: true},
		{name: "validation", provider: &fakeLLM{}, command: validCommand(" "), wantResult: OutcomeValidation},
		{name: "timeout", provider: &fakeLLM{response: generationTestResponse("", &llm.ProviderError{Kind: llm.ErrorTimeout}), wait: true}, command: validCommand("Explain fractions"), timeout: time.Millisecond, wantResult: OutcomeTimeout, wantMetric: "assistant_timeout_total", generation: true},
		{name: "provider 429", provider: &fakeLLM{response: generationTestResponse("", &llm.ProviderError{Kind: llm.ErrorRateLimit}), err: &llm.ProviderError{Kind: llm.ErrorRateLimit}}, command: validCommand("Explain fractions"), wantResult: OutcomeProvider429, wantMetric: "assistant_rate_limited_total", generation: true},
		{name: "malformed", provider: &fakeLLM{response: generationTestResponse("", &llm.ProviderError{Kind: llm.ErrorMalformed}), err: &llm.ProviderError{Kind: llm.ErrorMalformed}}, command: validCommand("Explain fractions"), wantResult: OutcomeMalformed, wantMetric: "assistant_malformed_total", generation: true},
		{name: "incomplete", provider: &fakeLLM{response: generationTestResponse("", &llm.ProviderError{Kind: llm.ErrorIncomplete}), err: &llm.ProviderError{Kind: llm.ErrorIncomplete}}, command: validCommand("Explain fractions"), wantResult: OutcomeIncomplete, wantMetric: "assistant_incomplete_total", generation: true},
		{name: "safety intervention", provider: &fakeLLM{}, command: validCommand("Я хочу покончить с собой"), wantResult: OutcomeSafetyIntervention, wantMetric: "assistant_safety_intervention_total"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			metrics := &capturingMetrics{}
			options := Options{CanaryGate: AllowAllCanaryGate(), Observe: observability.Hooks{Metrics: metrics}, LLMTimeout: test.timeout, RateLimiter: test.limiter}
			service := NewServiceWithOptions(persona.NewService(), test.provider, &fakeTTS{}, options)
			_, _ = service.Message(context.Background(), test.command)
			assertOneAssistantOutcome(t, metrics, test.wantResult)
			if test.wantMetric != "" && len(metrics.named(test.wantMetric)) != 1 {
				t.Fatalf("specialized metric %s was not emitted exactly once", test.wantMetric)
			}
			generationRequests := metrics.named("assistant_generation_requests_total")
			generationLatencies := metrics.named("assistant_generation_latency_ms")
			wantGenerationCount := 0
			if test.generation {
				wantGenerationCount = 1
			}
			if len(generationRequests) != wantGenerationCount || len(generationLatencies) != wantGenerationCount {
				t.Fatalf("generation contract violated: requests=%d latencies=%d want=%d", len(generationRequests), len(generationLatencies), wantGenerationCount)
			}
			if test.generation && generationRequests[0].Tags["provider"] != "alem" {
				t.Fatalf("known failed provider attribution was lost: %#v", generationRequests[0].Tags)
			}
		})
	}
}

func TestAssistantReadyAnswerGuardEmitsOneTerminalOutcome(t *testing.T) {
	studentID, sessionID := uuid.New(), uuid.New()
	repository := newMemorySessionRepository(studentID, sessionID, 7)
	provider := &capturingSessionProvider{text: "Ответ: 42. Полное решение готово."}
	metrics := &capturingMetrics{}
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{
		Enabled: &enabled, CanaryGate: AllowAllCanaryGate(), SessionRepository: repository,
		Observe: observability.Hooks{Metrics: metrics},
	})
	_, err := service.SendSessionMessage(context.Background(), SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: uuid.NewString(),
		Text: "Дай готовое полное решение домашнего задания",
	})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	assertOneAssistantOutcome(t, metrics, OutcomeReadyAnswerGuard)
	assertOneGenerationOutcome(t, metrics, OutcomeSuccess)
	if len(metrics.named("assistant_ready_answer_guard_total")) != 1 {
		t.Fatal("ready-answer guard counter was not emitted exactly once")
	}
}

func TestAssistantOwnRateLimitEmitsOneTerminalOutcome(t *testing.T) {
	metrics := &capturingMetrics{}
	limiter := ratelimit.NewInMemory(ratelimit.Config{Limit: 1, Window: time.Minute, MaxIdentities: 10})
	if !limiter.Allow(testStudentID).Allowed {
		t.Fatal("failed to prime rate limiter")
	}
	provider := &fakeLLM{response: llm.Response{Text: "must not run"}}
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{
		CanaryGate: AllowAllCanaryGate(), RateLimiter: limiter,
		Observe: observability.Hooks{Metrics: metrics},
	})
	command := validCommand("Explain fractions")
	command.EnforceRateLimit = true
	_, err := service.Message(context.Background(), command)
	if !apperrors.Is(err, "assistant_rate_limited") || provider.calls != 0 {
		t.Fatalf("unexpected rate-limit behavior: err=%v provider_calls=%d", err, provider.calls)
	}
	assertOneAssistantOutcome(t, metrics, OutcomeRateLimited)
	assertNoGenerationOutcome(t, metrics)
	if len(metrics.named("assistant_rate_limited_total")) != 1 {
		t.Fatal("assistant rate-limit counter was not emitted exactly once")
	}
}

func TestAssistantCanaryDenialEmitsOneOutcomeWithoutProviderCall(t *testing.T) {
	allowed := uuid.New()
	denied := uuid.New()
	gate, err := NewCanaryGate(RolloutModeAllowlist, []uuid.UUID{allowed})
	if err != nil {
		t.Fatal(err)
	}
	provider := &fakeLLM{response: llm.Response{Text: "must not run"}}
	metrics := &capturingMetrics{}
	enabled := true
	service := NewServiceWithOptions(nil, provider, nil, Options{
		Enabled: &enabled, CanaryGate: gate, Observe: observability.Hooks{Metrics: metrics},
	})
	_, err = service.Message(context.Background(), MessageCommand{StudentID: denied.String(), Mode: ModeTutor, GradeLevel: 7, Text: "synthetic"})
	if !apperrors.Is(err, "assistant_unavailable") || provider.calls != 0 {
		t.Fatalf("unexpected denial: err=%v provider_calls=%d", err, provider.calls)
	}
	assertOneAssistantOutcome(t, metrics, OutcomeCanaryDenied)
	assertNoGenerationOutcome(t, metrics)
	if len(metrics.named("assistant_canary_denied_total")) != 1 {
		t.Fatal("canary denial counter was not emitted exactly once")
	}
}

func assertOneAssistantOutcome(t *testing.T, metrics *capturingMetrics, want string) {
	t.Helper()
	requests := metrics.named("assistant_requests_total")
	latencies := metrics.named("assistant_latency_ms")
	if len(requests) != 1 || len(latencies) != 1 {
		t.Fatalf("terminal contract violated: requests=%d latencies=%d calls=%#v", len(requests), len(latencies), metrics.calls)
	}
	if requests[0].Tags["result"] != want {
		t.Fatalf("result=%q want=%q tags=%#v", requests[0].Tags["result"], want, requests[0].Tags)
	}
	if safeOperation(requests[0].Tags["operation"]) != requests[0].Tags["operation"] || requests[0].Tags["operation"] == telemetryUnknown {
		t.Fatalf("service operation is missing or invalid: %#v", requests[0].Tags)
	}
	assertMetricTagsAllowed(t, metrics)
}

func assertOneGenerationOutcome(t *testing.T, metrics *capturingMetrics, want string) {
	t.Helper()
	requests := metrics.named("assistant_generation_requests_total")
	latencies := metrics.named("assistant_generation_latency_ms")
	if len(requests) != 1 || len(latencies) != 1 || requests[0].Tags["result"] != want {
		t.Fatalf("generation terminal contract violated: requests=%#v latencies=%#v", requests, latencies)
	}
}

func assertNoGenerationOutcome(t *testing.T, metrics *capturingMetrics) {
	t.Helper()
	if len(metrics.named("assistant_generation_requests_total")) != 0 || len(metrics.named("assistant_generation_latency_ms")) != 0 {
		t.Fatalf("unexpected generation metrics: %#v", metrics.calls)
	}
}

func assertMetricTagsAllowed(t *testing.T, metrics *capturingMetrics) {
	t.Helper()
	allowedTags := map[string]bool{
		"result": true, "error_kind": true, "provider": true, "model": true,
		"locale": true, "mode": true, "operation": true, "stage": true,
		"finish_reason": true, "fallback_attempted": true, "fallback_succeeded": true,
		"primary_error_kind": true, "intent": true, "safety_category": true,
	}
	for _, call := range metrics.calls {
		for key := range call.Tags {
			if !allowedTags[key] {
				t.Fatalf("metric %s used forbidden tag %q", call.Name, key)
			}
		}
		assertMetricValuesAllowed(t, call)
	}
}

func assertMetricValuesAllowed(t *testing.T, call capturedMetric) {
	t.Helper()
	assistantOutcomes := []string{
		OutcomeSuccess, OutcomeCanaryDenied, OutcomeValidation, OutcomeRateLimited,
		OutcomeSafetyIntervention, OutcomeReadyAnswerGuard, OutcomeTimeout,
		OutcomeProvider4xx, OutcomeProvider429, OutcomeProvider5xx,
		OutcomeProviderUnavailable, OutcomeMalformed, OutcomeIncomplete,
		OutcomePersistenceError, OutcomeInternalError, telemetryNone,
	}
	metricResults := append(append([]string{}, assistantOutcomes...),
		"disabled", "wrong_owner/not_found", "invalid_content", "credentials")
	allowed := map[string]map[string]bool{
		"result":             setOf(metricResults...),
		"error_kind":         setOf(metricResults...),
		"provider":           setOf("alem", "deterministic", telemetryUnknown, telemetryNone),
		"model":              setOf("gemma4", "qwen3-8", "deterministic", telemetryUnknown, telemetryNone),
		"locale":             setOf("ru", "kk", "other"),
		"mode":               setOf("legacy", "voice", "text"),
		"operation":          setOf(OperationLegacyMessage, OperationSessionCreate, OperationSessionList, OperationSessionMessagesList, OperationSessionSend, OperationSessionDelete, OperationSpeechAuthorization),
		"stage":              setOf(string(llm.StagePrimary), string(llm.StageFallback), telemetryUnknown, telemetryNone),
		"finish_reason":      setOf(string(llm.FinishReasonStop), string(llm.FinishReasonLength), string(llm.FinishReasonMissing), string(llm.FinishReasonOther), telemetryNone),
		"fallback_attempted": setOf("true", "false"),
		"fallback_succeeded": setOf("true", "false"),
		"primary_error_kind": setOf(assistantOutcomes...),
		"intent": setOf(
			string(tutoring.IntentGeneralQuestion), string(tutoring.IntentConceptExplanation),
			string(tutoring.IntentHomeworkHelp), string(tutoring.IntentRequestReadyAnswer),
			string(tutoring.IntentCheckStudentAttempt), string(tutoring.IntentLearningAdvice),
			string(tutoring.IntentAcademicContextOffer), telemetryUnknown,
		),
		"safety_category": setOf(
			string(safety.CategoryNone), string(safety.CategorySelfHarm), string(safety.CategoryViolenceOrAbuse),
			string(safety.CategoryBullying), string(safety.CategorySexualSafety), string(safety.CategoryDangerousOrIllegal),
			string(safety.CategoryMedicalHighStakes), string(safety.CategoryPrivacyOrSecrets),
			string(safety.CategoryHarassment), string(safety.CategoryUnknownRisk), telemetryUnknown,
		),
	}
	for key, values := range allowed {
		if value, ok := call.Tags[key]; ok && !values[value] {
			t.Fatalf("metric %s used non-allowlisted %s=%q", call.Name, key, value)
		}
	}
}

func setOf(values ...string) map[string]bool {
	result := make(map[string]bool, len(values))
	for _, value := range values {
		result[value] = true
	}
	return result
}

func generationTestResponse(text string, err error) llm.Response {
	finishReason := llm.FinishReasonStop
	if providerErr := new(llm.ProviderError); errors.As(err, &providerErr) {
		switch providerErr.Kind {
		case llm.ErrorIncomplete:
			finishReason = llm.FinishReasonLength
		case llm.ErrorMalformed:
			finishReason = llm.FinishReasonMissing
		}
	}
	response := llm.Response{
		Text: text, Provider: "alem", Model: "gemma4", Stage: llm.StagePrimary, FinishReason: finishReason,
	}
	var errorKind llm.ErrorKind
	if providerErr := new(llm.ProviderError); errors.As(err, &providerErr) {
		errorKind = providerErr.Kind
	}
	response.Attempts = []llm.Attempt{{
		Provider: "alem", Model: "gemma4", Stage: llm.StagePrimary,
		FinishReason: finishReason, ErrorKind: errorKind, LatencyMS: 1,
	}}
	return response
}

func TestSessionCRUDDoesNotEmitGenerationMetrics(t *testing.T) {
	studentID, sessionID := uuid.New(), uuid.New()
	repository := newMemorySessionRepository(studentID, sessionID, 7)
	metrics := &capturingMetrics{}
	enabled := true
	service := NewServiceWithOptions(nil, &fakeLLM{}, nil, Options{
		Enabled: &enabled, CanaryGate: AllowAllCanaryGate(), SessionRepository: repository,
		Observe: observability.Hooks{Metrics: metrics},
	})
	if _, err := service.CreateSession(context.Background(), studentID.String()); err != nil {
		t.Fatal(err)
	}
	if _, err := service.ListSessions(context.Background(), studentID.String(), 10, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := service.ListSessionMessages(context.Background(), studentID.String(), sessionID.String(), 10, ""); err != nil {
		t.Fatal(err)
	}
	if err := service.DeleteSession(context.Background(), studentID.String(), sessionID.String()); err != nil {
		t.Fatal(err)
	}
	if len(metrics.named("assistant_generation_requests_total")) != 0 || len(metrics.named("assistant_generation_latency_ms")) != 0 {
		t.Fatalf("CRUD emitted generation metrics: %#v", metrics.calls)
	}
	requests := metrics.named("assistant_requests_total")
	wantOperations := []string{OperationSessionCreate, OperationSessionList, OperationSessionMessagesList, OperationSessionDelete}
	if len(requests) != len(wantOperations) {
		t.Fatalf("service requests=%d want=%d calls=%#v", len(requests), len(wantOperations), metrics.calls)
	}
	for i, want := range wantOperations {
		if requests[i].Tags["operation"] != want || requests[i].Tags["provider"] != telemetryNone || requests[i].Tags["model"] != telemetryNone {
			t.Fatalf("CRUD tags=%#v want_operation=%s", requests[i].Tags, want)
		}
	}
	assertMetricTagsAllowed(t, metrics)
}

func TestFallbackGenerationEmitsOneLogicalAndTwoAttemptOutcomes(t *testing.T) {
	metrics := &capturingMetrics{}
	response := llm.Response{
		Text: "fallback answer", Provider: "alem", Model: "qwen3-8", Stage: llm.StageFallback,
		FinishReason: llm.FinishReasonStop, FallbackAttempted: true, FallbackSucceeded: true,
		PrimaryErrorKind: llm.ErrorServer,
		Attempts: []llm.Attempt{
			{Provider: "alem", Model: "gemma4", Stage: llm.StagePrimary, FinishReason: llm.FinishReasonMissing, ErrorKind: llm.ErrorServer, LatencyMS: 2},
			{Provider: "alem", Model: "qwen3-8", Stage: llm.StageFallback, FinishReason: llm.FinishReasonStop, LatencyMS: 3},
		},
	}
	provider := &fakeLLM{response: response}
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{
		CanaryGate: AllowAllCanaryGate(), Observe: observability.Hooks{Metrics: metrics},
	})
	if _, err := service.Message(context.Background(), validCommand("Explain fractions")); err != nil {
		t.Fatal(err)
	}
	assertOneAssistantOutcome(t, metrics, OutcomeSuccess)
	assertOneGenerationOutcome(t, metrics, OutcomeSuccess)
	if len(metrics.named("assistant_generation_attempts_total")) != 2 || len(metrics.named("assistant_generation_attempt_latency_ms")) != 2 {
		t.Fatalf("attempt contract violated: %#v", metrics.calls)
	}
	generation := metrics.named("assistant_generation_requests_total")[0]
	if generation.Tags["model"] != "qwen3-8" || generation.Tags["stage"] != string(llm.StageFallback) ||
		generation.Tags["fallback_attempted"] != "true" || generation.Tags["fallback_succeeded"] != "true" ||
		generation.Tags["primary_error_kind"] != OutcomeProvider5xx {
		t.Fatalf("fallback logical tags=%#v", generation.Tags)
	}
	assertMetricTagsAllowed(t, metrics)
}

func TestTelemetryMapsNonAllowlistedModelToUnknown(t *testing.T) {
	metrics := &capturingMetrics{}
	recorder := newAssistantGenerationOutcome(metrics, "ru-KZ", InputModeText)
	response := llm.Response{Text: "answer", Provider: "alem", Model: "unbounded-model-id", Stage: llm.StagePrimary, FinishReason: llm.FinishReasonStop}
	recorder.Finish(response, nil)
	assertOneGenerationOutcome(t, metrics, OutcomeSuccess)
	if got := metrics.named("assistant_generation_requests_total")[0].Tags["model"]; got != telemetryUnknown {
		t.Fatalf("model=%q want=%q", got, telemetryUnknown)
	}
	assertMetricTagsAllowed(t, metrics)
}

type telemetrySpeechAuthorizer struct {
	allow         bool
	authorization speechauth.Authorization
	err           error
}

func (*telemetrySpeechAuthorizer) Enabled() bool { return true }
func (s *telemetrySpeechAuthorizer) AllowRequest(string) bool {
	return s.allow
}
func (s *telemetrySpeechAuthorizer) Authorize(context.Context, string, string, string, string) (speechauth.Authorization, error) {
	return s.authorization, s.err
}

func TestSpeechTerminalOutcomesEmitExactlyOnce(t *testing.T) {
	tests := []struct {
		name       string
		broker     *telemetrySpeechAuthorizer
		wantResult string
	}{
		{name: "success", broker: &telemetrySpeechAuthorizer{allow: true, authorization: speechauth.Authorization{Token: "SENSITIVE_TOKEN_91A"}}, wantResult: "success"},
		{name: "credentials", broker: &telemetrySpeechAuthorizer{allow: true, err: apperrors.New(503, "speech_credentials", "unavailable", nil)}, wantResult: "credentials"},
		{name: "rate limited", broker: &telemetrySpeechAuthorizer{allow: false}, wantResult: "rate_limited"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			studentID, sessionID, messageID := uuid.New(), uuid.New(), uuid.New()
			repository := &speechRepo{
				memorySessionRepository: newMemorySessionRepository(studentID, sessionID, 7),
				message:                 SessionMessage{ID: messageID.String(), SessionID: sessionID.String(), Role: "assistant", Content: "SENSITIVE_TRANSCRIPT_4D2"},
				inputMode:               InputModeVoice,
			}
			metrics := &capturingMetrics{}
			enabled := true
			service := NewServiceWithOptions(nil, nil, nil, Options{
				Enabled: &enabled, VoiceInputEnabled: &enabled, CanaryGate: AllowAllCanaryGate(),
				SessionRepository: repository, SpeechBroker: test.broker,
				Observe: observability.Hooks{Metrics: metrics},
			})
			_, _ = service.SpeechAuthorization(context.Background(), studentID.String(), sessionID.String(), messageID.String())
			issuance := metrics.named("speech_token_issuance_total")
			latency := metrics.named("speech_token_issuance_latency_ms")
			if len(issuance) != 1 || len(latency) != 1 || issuance[0].Tags["result"] != test.wantResult {
				t.Fatalf("speech terminal contract violated: issuance=%#v latency=%#v", issuance, latency)
			}
			assertMetricTagsAllowed(t, metrics)
			encoded, err := json.Marshal(metrics.calls)
			if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(string(encoded), "SENSITIVE_TOKEN_91A") || strings.Contains(string(encoded), "SENSITIVE_TRANSCRIPT_4D2") {
				t.Fatalf("speech telemetry leaked token or transcript: %s", encoded)
			}
		})
	}
}

func TestAssistantTelemetryContainsNoSyntheticSensitiveValues(t *testing.T) {
	studentID, sessionID := uuid.New(), uuid.New()
	promptValue := "Explain fractions marker 9AF"
	historyValue := "Prior learning marker 2BC"
	responseValue := "Fraction guidance marker 7C1"
	authorizationValue := "AUTHVAL_5E8"
	secretValue := "SECVAL_3D4"
	provider := &capturingSessionProvider{text: responseValue}
	metrics := &capturingMetrics{}
	enabled := true
	repository := newMemorySessionRepository(studentID, sessionID, 7)
	historyID := uuid.New()
	repository.exchanges[historyID] = StoredExchange{
		User:      SessionMessage{ID: uuid.NewString(), SessionID: sessionID.String(), Role: "user", Content: historyValue + authorizationValue + secretValue},
		Assistant: SessionMessage{ID: uuid.NewString(), SessionID: sessionID.String(), Role: "assistant", Content: "safe prior answer"},
	}
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{
		Enabled: &enabled, CanaryGate: AllowAllCanaryGate(), SessionRepository: repository,
		Observe: observability.Hooks{Metrics: metrics},
	})
	_, err := service.SendSessionMessage(context.Background(), SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: uuid.NewString(), Text: promptValue,
	})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	assertOneAssistantOutcome(t, metrics, OutcomeSuccess)
	assertOneGenerationOutcome(t, metrics, OutcomeSuccess)
	if got := metrics.named("assistant_requests_total")[0].Tags["operation"]; got != OperationSessionSend {
		t.Fatalf("operation=%q want=%q", got, OperationSessionSend)
	}

	encoded, err := json.Marshal(metrics.calls)
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{studentID.String(), sessionID.String(), promptValue, historyValue, responseValue, authorizationValue, secretValue} {
		if strings.Contains(string(encoded), forbidden) {
			t.Fatalf("telemetry leaked synthetic sensitive value %q: %s", forbidden, encoded)
		}
	}
}

func TestSpeechErrorClassifierDoesNotExposeFreeFormErrors(t *testing.T) {
	if got := speechResultFromError(errors.New("SENSITIVE_FREE_FORM_ERROR")); got != "internal_error" {
		t.Fatalf("unexpected free-form classification: %q", got)
	}
}
