package assistant

import (
	"context"
	"errors"
	"strings"
	"sync"
	"time"

	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/safety"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tutoring"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
	"github.com/kundi/kundi/backend/internal/platform/observability"
)

const (
	OutcomeSuccess             = "success"
	OutcomeCanaryDenied        = "canary_denied"
	OutcomeValidation          = "validation"
	OutcomeRateLimited         = "rate_limited"
	OutcomeSafetyIntervention  = "safety_intervention"
	OutcomeReadyAnswerGuard    = "ready_answer_guard"
	OutcomeTimeout             = "timeout"
	OutcomeProvider4xx         = "provider_4xx"
	OutcomeProvider429         = "provider_429"
	OutcomeProvider5xx         = "provider_5xx"
	OutcomeProviderUnavailable = "provider_unavailable"
	OutcomeMalformed           = "malformed"
	OutcomeIncomplete          = "incomplete"
	OutcomePersistenceError    = "persistence_error"
	OutcomeInternalError       = "internal_error"
)

const (
	telemetryUnknown = "unknown"
	telemetryNone    = "none"
)

const (
	OperationLegacyMessage       = "legacy_message"
	OperationSessionCreate       = "session_create"
	OperationSessionList         = "session_list"
	OperationSessionMessagesList = "session_messages_list"
	OperationSessionSend         = "session_send"
	OperationSessionDelete       = "session_delete"
	OperationSpeechAuthorization = "speech_authorization"
)

type assistantOutcomeRecorder struct {
	once              sync.Once
	metrics           observability.Metrics
	startedAt         time.Time
	operation         string
	mode              string
	locale            string
	provider          string
	model             string
	stage             string
	finishReason      string
	fallbackAttempted string
	fallbackSucceeded string
	primaryErrorKind  string
	intent            string
	safety            string
	result            string
	errorKind         string
}

func newAssistantOutcome(metrics observability.Metrics, operation, mode string) *assistantOutcomeRecorder {
	return &assistantOutcomeRecorder{
		metrics: metrics, startedAt: time.Now(), operation: safeOperation(operation), mode: safeMode(mode), locale: "other",
		provider: telemetryNone, model: telemetryNone, stage: telemetryNone, finishReason: telemetryNone,
		fallbackAttempted: "false", fallbackSucceeded: "false", primaryErrorKind: telemetryNone,
		intent: telemetryUnknown, safety: telemetryNone,
	}
}

func (r *assistantOutcomeRecorder) SetLocale(raw string) {
	r.locale = safeLocale(raw)
}

func (r *assistantOutcomeRecorder) SetExecution(response llm.Response) {
	r.provider = safeProvider(response.Provider)
	r.model = safeModel(response.Model)
	r.stage = safeStage(string(response.Stage))
	r.finishReason = safeFinishReason(string(response.FinishReason))
	r.fallbackAttempted = safeBool(response.FallbackAttempted)
	r.fallbackSucceeded = safeBool(response.FallbackSucceeded)
	r.primaryErrorKind = safeProviderErrorKind(response.PrimaryErrorKind)
}

func (r *assistantOutcomeRecorder) SetAnalysis(analysis tutoring.Analysis) {
	r.intent = safeIntent(string(analysis.Intent))
}

func (r *assistantOutcomeRecorder) SetSafety(category safety.SafetyCategory) {
	r.safety = safeSafetyCategory(string(category))
}

func (r *assistantOutcomeRecorder) SetResult(result, errorKind string) {
	r.result = safeAssistantOutcome(result)
	r.errorKind = safeErrorKind(errorKind)
}

func (r *assistantOutcomeRecorder) Finish(err error) {
	r.once.Do(func() {
		if r.result == "" {
			r.result, r.errorKind = assistantOutcomeFromError(err)
		}
		tags := map[string]string{
			"result": r.result, "error_kind": r.errorKind,
			"provider": r.provider, "model": r.model,
			"locale": r.locale, "mode": r.mode, "operation": r.operation,
			"stage": r.stage, "finish_reason": r.finishReason,
			"fallback_attempted": r.fallbackAttempted, "fallback_succeeded": r.fallbackSucceeded,
			"primary_error_kind": r.primaryErrorKind, "intent": r.intent,
			"safety_category": r.safety,
		}
		r.metrics.Incr("assistant_requests_total", tags)
		r.metrics.Observe("assistant_latency_ms", float64(time.Since(r.startedAt).Microseconds())/1000, tags)
		specializedAssistantMetric(r.metrics, r.result, tags)
	})
}

func specializedAssistantMetric(metrics observability.Metrics, result string, tags map[string]string) {
	name := ""
	switch result {
	case OutcomeTimeout:
		name = "assistant_timeout_total"
	case OutcomeRateLimited, OutcomeProvider429:
		name = "assistant_rate_limited_total"
	case OutcomeMalformed:
		name = "assistant_malformed_total"
	case OutcomeIncomplete:
		name = "assistant_incomplete_total"
	case OutcomeSafetyIntervention:
		name = "assistant_safety_intervention_total"
	case OutcomeReadyAnswerGuard:
		name = "assistant_ready_answer_guard_total"
	case OutcomeCanaryDenied:
		name = "assistant_canary_denied_total"
	}
	if name != "" {
		metrics.Incr(name, tags)
	}
}

func assistantOutcomeFromError(err error) (string, string) {
	if err == nil {
		return OutcomeSuccess, telemetryNone
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return OutcomeTimeout, OutcomeTimeout
	}
	var appErr *apperrors.Error
	if errors.As(err, &appErr) {
		switch appErr.Code {
		case "assistant_unavailable":
			return OutcomeCanaryDenied, OutcomeCanaryDenied
		case "assistant_rate_limited":
			return OutcomeRateLimited, OutcomeRateLimited
		case "assistant_provider_rate_limited":
			return OutcomeProvider429, OutcomeProvider429
		case "assistant_provider_invalid_response":
			return OutcomeMalformed, OutcomeMalformed
		case "assistant_provider_unavailable":
			return OutcomeProviderUnavailable, OutcomeProviderUnavailable
		case "assistant_session_create_failed", "assistant_session_delete_failed", "assistant_message_save_failed":
			return OutcomePersistenceError, OutcomePersistenceError
		}
		if appErr.StatusCode >= 400 && appErr.StatusCode < 500 {
			return OutcomeValidation, OutcomeValidation
		}
	}
	return OutcomeInternalError, OutcomeInternalError
}

func assistantOutcomeFromProvider(err error, responsePresent bool) (string, string) {
	if err == nil && responsePresent {
		return OutcomeSuccess, telemetryNone
	}
	if err == nil && !responsePresent {
		return OutcomeMalformed, OutcomeMalformed
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return OutcomeTimeout, OutcomeTimeout
	}
	var providerErr *llm.ProviderError
	if errors.As(err, &providerErr) {
		switch providerErr.Kind {
		case llm.ErrorClient:
			return OutcomeProvider4xx, OutcomeProvider4xx
		case llm.ErrorRateLimit:
			return OutcomeProvider429, OutcomeProvider429
		case llm.ErrorServer:
			return OutcomeProvider5xx, OutcomeProvider5xx
		case llm.ErrorUnavailable:
			return OutcomeProviderUnavailable, OutcomeProviderUnavailable
		case llm.ErrorTimeout:
			return OutcomeTimeout, OutcomeTimeout
		case llm.ErrorMalformed:
			return OutcomeMalformed, OutcomeMalformed
		case llm.ErrorIncomplete:
			return OutcomeIncomplete, OutcomeIncomplete
		}
	}
	return OutcomeInternalError, OutcomeInternalError
}

func safeAssistantOutcome(raw string) string {
	switch raw {
	case OutcomeSuccess, OutcomeCanaryDenied, OutcomeValidation, OutcomeRateLimited,
		OutcomeSafetyIntervention, OutcomeReadyAnswerGuard, OutcomeTimeout,
		OutcomeProvider4xx, OutcomeProvider429, OutcomeProvider5xx,
		OutcomeProviderUnavailable, OutcomeMalformed, OutcomeIncomplete, OutcomePersistenceError,
		OutcomeInternalError:
		return raw
	default:
		return OutcomeInternalError
	}
}

func safeErrorKind(raw string) string {
	if raw == "" || raw == telemetryNone {
		return telemetryNone
	}
	return safeAssistantOutcome(raw)
}

func safeMode(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "legacy":
		return "legacy"
	case "voice":
		return "voice"
	default:
		return "text"
	}
}

func safeOperation(raw string) string {
	switch raw {
	case OperationLegacyMessage, OperationSessionCreate, OperationSessionList,
		OperationSessionMessagesList, OperationSessionSend, OperationSessionDelete,
		OperationSpeechAuthorization:
		return raw
	default:
		return telemetryUnknown
	}
}

func safeLocale(raw string) string {
	normalized := strings.ToLower(strings.TrimSpace(raw))
	switch {
	case strings.HasPrefix(normalized, "ru"):
		return "ru"
	case strings.HasPrefix(normalized, "kk"):
		return "kk"
	default:
		return "other"
	}
}

func safeProvider(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case telemetryNone:
		return telemetryNone
	case "alem":
		return "alem"
	case "deterministic":
		return "deterministic"
	default:
		return telemetryUnknown
	}
}

func safeModel(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case telemetryNone:
		return telemetryNone
	case "gemma4":
		return "gemma4"
	case "qwen3-8":
		return "qwen3-8"
	case "deterministic":
		return "deterministic"
	default:
		return telemetryUnknown
	}
}

func safeStage(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case telemetryNone:
		return telemetryNone
	case string(llm.StagePrimary):
		return string(llm.StagePrimary)
	case string(llm.StageFallback):
		return string(llm.StageFallback)
	default:
		return telemetryUnknown
	}
}

func safeFinishReason(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case telemetryNone:
		return telemetryNone
	case string(llm.FinishReasonStop):
		return string(llm.FinishReasonStop)
	case string(llm.FinishReasonLength):
		return string(llm.FinishReasonLength)
	case "", string(llm.FinishReasonMissing):
		return string(llm.FinishReasonMissing)
	case string(llm.FinishReasonOther):
		return string(llm.FinishReasonOther)
	default:
		return string(llm.FinishReasonOther)
	}
}

func safeBool(value bool) string {
	if value {
		return "true"
	}
	return "false"
}

func safeProviderErrorKind(kind llm.ErrorKind) string {
	if kind == "" {
		return telemetryNone
	}
	result, _ := assistantOutcomeFromProvider(&llm.ProviderError{Kind: kind}, false)
	return safeAssistantOutcome(result)
}

type assistantGenerationOutcomeRecorder struct {
	once      sync.Once
	metrics   observability.Metrics
	startedAt time.Time
	locale    string
	mode      string
}

func newAssistantGenerationOutcome(metrics observability.Metrics, locale, mode string) *assistantGenerationOutcomeRecorder {
	return &assistantGenerationOutcomeRecorder{
		metrics: metrics, startedAt: time.Now(), locale: safeLocale(locale), mode: safeMode(mode),
	}
}

func (r *assistantGenerationOutcomeRecorder) Finish(response llm.Response, err error) {
	r.once.Do(func() {
		result, errorKind := assistantOutcomeFromProvider(err, strings.TrimSpace(response.Text) != "")
		tags := generationTags(response, result, errorKind)
		tags["locale"] = r.locale
		tags["mode"] = r.mode
		r.metrics.Incr("assistant_generation_requests_total", tags)
		r.metrics.Observe("assistant_generation_latency_ms", float64(time.Since(r.startedAt).Microseconds())/1000, tags)

		attempts := response.Attempts
		if len(attempts) > 2 {
			attempts = attempts[:2]
		}
		for _, attempt := range attempts {
			attemptResult, attemptErrorKind := assistantAttemptOutcome(attempt)
			attemptTags := map[string]string{
				"result": attemptResult, "error_kind": attemptErrorKind,
				"provider": safeProvider(attempt.Provider), "model": safeModel(attempt.Model),
				"stage":         safeStage(string(attempt.Stage)),
				"finish_reason": safeFinishReason(string(attempt.FinishReason)),
			}
			r.metrics.Incr("assistant_generation_attempts_total", attemptTags)
			r.metrics.Observe("assistant_generation_attempt_latency_ms", max(0, attempt.LatencyMS), attemptTags)
		}
	})
}

func generationTags(response llm.Response, result, errorKind string) map[string]string {
	return map[string]string{
		"result": safeAssistantOutcome(result), "error_kind": safeErrorKind(errorKind),
		"provider": safeProvider(response.Provider), "model": safeModel(response.Model),
		"stage":              safeStage(string(response.Stage)),
		"finish_reason":      safeFinishReason(string(response.FinishReason)),
		"fallback_attempted": safeBool(response.FallbackAttempted),
		"fallback_succeeded": safeBool(response.FallbackSucceeded),
		"primary_error_kind": safeProviderErrorKind(response.PrimaryErrorKind),
	}
}

func assistantAttemptOutcome(attempt llm.Attempt) (string, string) {
	if attempt.ErrorKind == "" {
		if attempt.FinishReason == llm.FinishReasonStop {
			return OutcomeSuccess, telemetryNone
		}
		return OutcomeMalformed, OutcomeMalformed
	}
	return assistantOutcomeFromProvider(&llm.ProviderError{Kind: attempt.ErrorKind}, false)
}

func safeIntent(raw string) string {
	switch tutoring.Intent(raw) {
	case tutoring.IntentGeneralQuestion, tutoring.IntentConceptExplanation,
		tutoring.IntentHomeworkHelp, tutoring.IntentRequestReadyAnswer,
		tutoring.IntentCheckStudentAttempt, tutoring.IntentLearningAdvice,
		tutoring.IntentAcademicContextOffer:
		return raw
	default:
		return telemetryUnknown
	}
}

func safeSafetyCategory(raw string) string {
	switch safety.SafetyCategory(raw) {
	case safety.CategoryNone, safety.CategorySelfHarm, safety.CategoryViolenceOrAbuse,
		safety.CategoryBullying, safety.CategorySexualSafety, safety.CategoryDangerousOrIllegal,
		safety.CategoryMedicalHighStakes, safety.CategoryPrivacyOrSecrets,
		safety.CategoryHarassment, safety.CategoryUnknownRisk:
		return raw
	default:
		return telemetryUnknown
	}
}

type speechOutcomeRecorder struct {
	once      sync.Once
	metrics   observability.Metrics
	startedAt time.Time
	locale    string
	result    string
	errorKind string
}

func newSpeechOutcome(metrics observability.Metrics) *speechOutcomeRecorder {
	return &speechOutcomeRecorder{metrics: metrics, startedAt: time.Now(), locale: "other"}
}

func (r *speechOutcomeRecorder) SetLocale(raw string) { r.locale = safeLocale(raw) }

func (r *speechOutcomeRecorder) SetResult(result string) {
	r.result = safeSpeechResult(result)
	if r.result == "success" || r.result == "disabled" {
		r.errorKind = telemetryNone
	} else {
		r.errorKind = r.result
	}
}

func (r *speechOutcomeRecorder) Finish(err error) {
	r.once.Do(func() {
		if r.result == "" {
			r.result = speechResultFromError(err)
			if r.result == "success" || r.result == "disabled" {
				r.errorKind = telemetryNone
			} else {
				r.errorKind = r.result
			}
		}
		tags := map[string]string{
			"result": r.result, "error_kind": r.errorKind, "locale": r.locale,
			"operation": OperationSpeechAuthorization,
		}
		r.metrics.Incr("speech_token_issuance_total", tags)
		r.metrics.Observe("speech_token_issuance_latency_ms", float64(time.Since(r.startedAt).Microseconds())/1000, tags)
		if r.result == "rate_limited" {
			r.metrics.Incr("speech_token_rate_limited_total", tags)
		}

		serviceResult, serviceErrorKind := assistantOutcomeFromSpeechResult(r.result)
		serviceTags := map[string]string{
			"result": serviceResult, "error_kind": serviceErrorKind,
			"provider": telemetryNone, "model": telemetryNone,
			"locale": r.locale, "mode": "voice", "operation": OperationSpeechAuthorization,
			"stage": telemetryNone, "finish_reason": telemetryNone,
			"fallback_attempted": "false", "fallback_succeeded": "false",
			"primary_error_kind": telemetryNone, "intent": telemetryUnknown,
			"safety_category": telemetryNone,
		}
		r.metrics.Incr("assistant_requests_total", serviceTags)
		r.metrics.Observe("assistant_latency_ms", float64(time.Since(r.startedAt).Microseconds())/1000, serviceTags)
		specializedAssistantMetric(r.metrics, serviceResult, serviceTags)
	})
}

func assistantOutcomeFromSpeechResult(result string) (string, string) {
	switch result {
	case "success", "disabled":
		return OutcomeSuccess, telemetryNone
	case "canary_denied":
		return OutcomeCanaryDenied, OutcomeCanaryDenied
	case "rate_limited":
		return OutcomeRateLimited, OutcomeRateLimited
	case "timeout":
		return OutcomeTimeout, OutcomeTimeout
	case "provider_unavailable", "credentials":
		return OutcomeProviderUnavailable, OutcomeProviderUnavailable
	case "wrong_owner/not_found", "invalid_content":
		return OutcomeValidation, OutcomeValidation
	default:
		return OutcomeInternalError, OutcomeInternalError
	}
}

func speechResultFromError(err error) string {
	if err == nil {
		return "success"
	}
	var appErr *apperrors.Error
	if !errors.As(err, &appErr) {
		return "internal_error"
	}
	switch appErr.Code {
	case "assistant_tts_disabled":
		return "disabled"
	case "assistant_unavailable":
		return "canary_denied"
	case "assistant_message_not_found", "assistant_session_not_found":
		return "wrong_owner/not_found"
	case "assistant_message_id_invalid", "assistant_session_id_invalid", "speech_content_invalid":
		return "invalid_content"
	case "speech_rate_limited", "speech_issuance_limit", "speech_busy", "speech_token_rate_limited":
		return "rate_limited"
	case "speech_configuration", "speech_credentials":
		return "credentials"
	case "speech_token_timeout":
		return "timeout"
	case "speech_message_unavailable", "speech_token_unavailable", "speech_token_invalid":
		return "provider_unavailable"
	default:
		return "internal_error"
	}
}

func safeSpeechResult(raw string) string {
	switch raw {
	case "success", "disabled", "canary_denied", "wrong_owner/not_found",
		"invalid_content", "rate_limited", "credentials", "timeout",
		"provider_unavailable", "internal_error":
		return raw
	default:
		return "internal_error"
	}
}
