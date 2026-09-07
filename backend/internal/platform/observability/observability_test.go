package observability

import (
	"bytes"
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func TestNewDefaultsToLogMode(t *testing.T) {
	buf := &bytes.Buffer{}
	logger := slog.New(slog.NewTextHandler(buf, nil))
	hooks := New(Config{}, logger)

	if _, ok := hooks.Metrics.(LogMetrics); !ok {
		t.Fatalf("expected LogMetrics by default")
	}
	if _, ok := hooks.Tracer.(LogTracer); !ok {
		t.Fatalf("expected LogTracer by default")
	}
}

func TestNewNoopMode(t *testing.T) {
	hooks := New(Config{Mode: "noop"}, nil)
	if _, ok := hooks.Metrics.(NoopMetrics); !ok {
		t.Fatalf("expected NoopMetrics in noop mode")
	}
	if _, ok := hooks.Tracer.(NoopTracer); !ok {
		t.Fatalf("expected NoopTracer in noop mode")
	}
}

func TestEnsureFillsNilHooks(t *testing.T) {
	h := Ensure(Hooks{})
	if h.Metrics == nil || h.Tracer == nil {
		t.Fatalf("ensure must provide defaults")
	}
}

func TestLogHooksEmitWithoutPanic(t *testing.T) {
	buf := &bytes.Buffer{}
	logger := slog.New(slog.NewTextHandler(buf, nil))
	hooks := New(Config{Mode: "log"}, logger)

	hooks.Metrics.Incr("backend.test.counter", map[string]string{"stage": "active"})
	hooks.Metrics.Observe("backend.test.latency", 10, map[string]string{"stage": "active"})
	ctx, finish := hooks.Tracer.Start(context.Background(), "backend.test.span")
	if ctx == nil {
		t.Fatalf("expected non-nil ctx")
	}
	finish(nil)

	out := buf.String()
	if out == "" {
		t.Fatalf("expected log output from observability hooks")
	}
}

func TestPrometheusModeExportsOnlyBoundedAssistantMetrics(t *testing.T) {
	hooks := New(Config{Mode: "prometheus"}, nil)
	if hooks.MetricsHandler == nil {
		t.Fatal("prometheus mode must expose a handler")
	}

	serviceTags := map[string]string{
		"result": "success", "error_kind": "none", "provider": "alem", "model": "gemma4",
		"locale": "kk", "mode": "text", "operation": "session_send", "stage": "primary",
		"finish_reason": "stop", "fallback_attempted": "false", "fallback_succeeded": "false",
		"primary_error_kind": "none", "intent": "homework_help", "safety_category": "none",
	}
	generationTags := map[string]string{
		"result": "success", "error_kind": "none", "provider": "alem", "model": "gemma4",
		"stage": "primary", "finish_reason": "stop", "fallback_attempted": "false",
		"fallback_succeeded": "false", "primary_error_kind": "none", "locale": "kk", "mode": "text",
	}
	attemptTags := map[string]string{
		"result": "success", "error_kind": "none", "provider": "alem", "model": "gemma4",
		"stage": "primary", "finish_reason": "stop",
	}
	hooks.Metrics.Incr("assistant_requests_total", serviceTags)
	hooks.Metrics.Observe("assistant_latency_ms", 125, serviceTags)
	hooks.Metrics.Incr("assistant_generation_requests_total", generationTags)
	hooks.Metrics.Observe("assistant_generation_latency_ms", 100, generationTags)
	hooks.Metrics.Incr("assistant_generation_attempts_total", attemptTags)
	hooks.Metrics.Observe("assistant_generation_attempt_latency_ms", 90, attemptTags)
	hooks.Metrics.Incr("backend.unbounded_metric_total", map[string]string{"student_id": "PRIVATE_MARKER"})

	recorder := httptest.NewRecorder()
	hooks.MetricsHandler.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("metrics status=%d", recorder.Code)
	}
	body := recorder.Body.String()
	for _, name := range []string{
		"assistant_requests_total", "assistant_latency_ms",
		"assistant_generation_requests_total", "assistant_generation_latency_ms",
		"assistant_generation_attempts_total", "assistant_generation_attempt_latency_ms",
	} {
		if !strings.Contains(body, name) {
			t.Fatalf("metrics output missing %s: %s", name, body)
		}
	}
	for _, forbidden := range []string{"backend_unbounded", "student_id", "PRIVATE_MARKER"} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("metrics output leaked %q: %s", forbidden, body)
		}
	}
}

func TestPrometheusMetricsReplaceUnboundedLabels(t *testing.T) {
	metrics := newPrometheusMetrics()
	metrics.Incr("assistant_generation_attempts_total", map[string]string{
		"result": "SENSITIVE_RESULT", "error_kind": "none", "provider": "alem",
		"model": "SENSITIVE_MODEL", "stage": "primary", "finish_reason": "stop",
		"prompt": "SENSITIVE_PROMPT",
	})

	handler := promhttp.HandlerFor(metrics.registry, promhttp.HandlerOpts{})
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	body := recorder.Body.String()
	for _, forbidden := range []string{"SENSITIVE_RESULT", "SENSITIVE_MODEL", "SENSITIVE_PROMPT", "prompt="} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("metrics output leaked %q: %s", forbidden, body)
		}
	}
	if !strings.Contains(body, `model="unknown"`) || !strings.Contains(body, `result="unknown"`) {
		t.Fatalf("unbounded values were not normalized: %s", body)
	}
}
