package observability

import (
	"strings"

	"github.com/prometheus/client_golang/prometheus"
)

var assistantLatencyBucketsMS = []float64{
	50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 15_000, 25_000, 30_000,
}

type prometheusMetricSpec struct {
	help   string
	labels []string
}

var prometheusCounterSpecs = map[string]prometheusMetricSpec{
	"assistant_requests_total": {
		help:   "Total Assistant service requests by bounded terminal outcome.",
		labels: assistantServiceLabels,
	},
	"assistant_generation_requests_total": {
		help:   "Total logical Assistant generation requests by bounded terminal outcome.",
		labels: assistantGenerationLabels,
	},
	"assistant_generation_attempts_total": {
		help:   "Total Assistant provider attempts by bounded terminal outcome.",
		labels: assistantAttemptLabels,
	},
}

var prometheusHistogramSpecs = map[string]prometheusMetricSpec{
	"assistant_latency_ms": {
		help:   "Assistant service request latency in milliseconds.",
		labels: assistantServiceLabels,
	},
	"assistant_generation_latency_ms": {
		help:   "Logical Assistant generation latency in milliseconds.",
		labels: assistantGenerationLabels,
	},
	"assistant_generation_attempt_latency_ms": {
		help:   "Assistant provider attempt latency in milliseconds.",
		labels: assistantAttemptLabels,
	},
}

var (
	assistantServiceLabels = []string{
		"result", "error_kind", "provider", "model", "locale", "mode", "operation",
		"stage", "finish_reason", "fallback_attempted", "fallback_succeeded",
		"primary_error_kind", "intent", "safety_category",
	}
	assistantGenerationLabels = []string{
		"result", "error_kind", "provider", "model", "stage", "finish_reason",
		"fallback_attempted", "fallback_succeeded", "primary_error_kind", "locale", "mode",
	}
	assistantAttemptLabels = []string{
		"result", "error_kind", "provider", "model", "stage", "finish_reason",
	}
)

type prometheusMetrics struct {
	registry   *prometheus.Registry
	counters   map[string]*prometheus.CounterVec
	histograms map[string]*prometheus.HistogramVec
}

func newPrometheusMetrics() *prometheusMetrics {
	registry := prometheus.NewRegistry()
	metrics := &prometheusMetrics{
		registry:   registry,
		counters:   make(map[string]*prometheus.CounterVec, len(prometheusCounterSpecs)),
		histograms: make(map[string]*prometheus.HistogramVec, len(prometheusHistogramSpecs)),
	}
	for name, spec := range prometheusCounterSpecs {
		counter := prometheus.NewCounterVec(prometheus.CounterOpts{Name: name, Help: spec.help}, spec.labels)
		registry.MustRegister(counter)
		metrics.counters[name] = counter
	}
	for name, spec := range prometheusHistogramSpecs {
		histogram := prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name: name, Help: spec.help, Buckets: assistantLatencyBucketsMS,
		}, spec.labels)
		registry.MustRegister(histogram)
		metrics.histograms[name] = histogram
	}
	return metrics
}

func (m *prometheusMetrics) Incr(name string, tags map[string]string) {
	counter, ok := m.counters[name]
	if !ok {
		return
	}
	counter.WithLabelValues(prometheusLabelValues(prometheusCounterSpecs[name].labels, tags)...).Inc()
}

func (m *prometheusMetrics) Observe(name string, value float64, tags map[string]string) {
	histogram, ok := m.histograms[name]
	if !ok {
		return
	}
	histogram.WithLabelValues(prometheusLabelValues(prometheusHistogramSpecs[name].labels, tags)...).Observe(value)
}

func prometheusLabelValues(labels []string, tags map[string]string) []string {
	values := make([]string, len(labels))
	for i, label := range labels {
		values[i] = boundedPrometheusLabel(label, tags[label])
	}
	return values
}

func boundedPrometheusLabel(label, raw string) string {
	value := strings.ToLower(strings.TrimSpace(raw))
	if allowedPrometheusLabelValues[label][value] {
		return value
	}
	return "unknown"
}

var allowedPrometheusLabelValues = map[string]map[string]bool{
	"result": set(
		"success", "canary_denied", "validation", "rate_limited", "safety_intervention",
		"ready_answer_guard", "timeout", "provider_4xx", "provider_429", "provider_5xx",
		"provider_unavailable", "malformed", "incomplete", "persistence_error", "internal_error", "unknown",
	),
	"error_kind": set(
		"none", "canary_denied", "validation", "rate_limited", "safety_intervention",
		"ready_answer_guard", "timeout", "provider_4xx", "provider_429", "provider_5xx",
		"provider_unavailable", "malformed", "incomplete", "persistence_error", "internal_error", "unknown",
	),
	"provider": set("alem", "deterministic", "none", "unknown"),
	"model":    set("gemma4", "qwen3-8", "deterministic", "none", "unknown"),
	"locale":   set("ru", "kk", "other", "unknown"),
	"mode":     set("legacy", "voice", "text", "unknown"),
	"operation": set(
		"legacy_message", "session_create", "session_list", "session_messages_list",
		"session_send", "session_delete", "speech_authorization", "unknown",
	),
	"stage":              set("primary", "fallback", "none", "unknown"),
	"finish_reason":      set("stop", "length", "missing", "other", "none", "unknown"),
	"fallback_attempted": set("true", "false", "unknown"),
	"fallback_succeeded": set("true", "false", "unknown"),
	"primary_error_kind": set(
		"none", "canary_denied", "validation", "rate_limited", "safety_intervention",
		"ready_answer_guard", "timeout", "provider_4xx", "provider_429", "provider_5xx",
		"provider_unavailable", "malformed", "incomplete", "persistence_error", "internal_error", "unknown",
	),
	"intent": set(
		"general_question", "concept_explanation", "homework_help", "request_ready_answer",
		"attempt_check", "learning_advice", "academic_context_offer", "unknown",
	),
	"safety_category": set(
		"none", "self_harm", "violence_or_abuse", "bullying", "sexual_safety",
		"dangerous_or_illegal", "medical_high_stakes", "privacy_or_secrets", "harassment",
		"unknown_risk", "unknown",
	),
}

func set(values ...string) map[string]bool {
	result := make(map[string]bool, len(values))
	for _, value := range values {
		result[value] = true
	}
	return result
}
