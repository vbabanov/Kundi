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
	OutcomePersistenceError    = "persistence_error"
	OutcomeInternalError       = "internal_error"
)

const (
	telemetryUnknown = "unknown"
	telemetryNone    = "none"
)

type assistantOutcomeRecorder struct {
	once         sync.Once
	metrics      observability.Metrics
	startedAt    time.Time
	mode         string
	locale       string
	provider     string
	model        string
	fallbackUsed string
	intent       string
	safety       string
	result       string
	errorKind    string
}

func newAssistantOutcome(metrics observability.Metrics, mode string) *assistantOutcomeRecorder {
	return &assistantOutcomeRecorder{
		metrics: metrics, startedAt: time.Now(), mode: safeMode(mode), locale: "other",
		provider: telemetryUnknown, model: telemetryUnknown, fallbackUsed: "false",
		intent: telemetryUnknown, safety: telemetryNone,
	}
}

func (r *assistantOutcomeRecorder) SetLocale(raw string) {
	r.locale = safeLocale(raw)
}

func (r *assistantOutcomeRecorder) SetProvider(provider, model string, fallbackUsed bool) {
	r.provider = safeProvider(provider)
	r.model = safeModel(model)
	if fallbackUsed {
		r.fallbackUsed = "true"
	}
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
			"locale": r.locale, "mode": r.mode,
			"fallback_used": r.fallbackUsed, "intent": r.intent,
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
		}
	}
	return OutcomeInternalError, OutcomeInternalError
}

func safeAssistantOutcome(raw string) string {
	switch raw {
	case OutcomeSuccess, OutcomeCanaryDenied, OutcomeValidation, OutcomeRateLimited,
		OutcomeSafetyIntervention, OutcomeReadyAnswerGuard, OutcomeTimeout,
		OutcomeProvider4xx, OutcomeProvider429, OutcomeProvider5xx,
		OutcomeProviderUnavailable, OutcomeMalformed, OutcomePersistenceError,
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
		tags := map[string]string{"result": r.result, "error_kind": r.errorKind, "locale": r.locale}
		r.metrics.Incr("speech_token_issuance_total", tags)
		r.metrics.Observe("speech_token_issuance_latency_ms", float64(time.Since(r.startedAt).Microseconds())/1000, tags)
		if r.result == "rate_limited" {
			r.metrics.Incr("speech_token_rate_limited_total", tags)
		}
		if r.result == "canary_denied" {
			r.metrics.Incr("assistant_canary_denied_total", map[string]string{
				"result": OutcomeCanaryDenied, "error_kind": OutcomeCanaryDenied,
				"provider": telemetryUnknown, "model": telemetryUnknown, "locale": r.locale,
				"mode": "voice", "fallback_used": "false", "intent": telemetryUnknown,
				"safety_category": telemetryNone,
			})
		}
	})
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
