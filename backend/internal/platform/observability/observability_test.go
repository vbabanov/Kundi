package observability

import (
	"bytes"
	"context"
	"log/slog"
	"testing"
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
