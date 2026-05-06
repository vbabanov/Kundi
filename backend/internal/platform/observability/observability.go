package observability

import (
	"context"
	"log/slog"
	"strings"
	"time"
)

// Metrics is a minimal seam for counters/histograms.
type Metrics interface {
	Incr(name string, tags map[string]string)
	Observe(name string, value float64, tags map[string]string)
}

type Tracer interface {
	Start(ctx context.Context, spanName string) (context.Context, func(err error))
}

type NoopMetrics struct{}

func (NoopMetrics) Incr(string, map[string]string)             {}
func (NoopMetrics) Observe(string, float64, map[string]string) {}

type NoopTracer struct{}

func (NoopTracer) Start(ctx context.Context, _ string) (context.Context, func(error)) {
	return ctx, func(error) {}
}

type Hooks struct {
	Metrics Metrics
	Tracer  Tracer
}

type Config struct {
	Mode string
}

func New(cfg Config, logger *slog.Logger) Hooks {
	mode := strings.ToLower(strings.TrimSpace(cfg.Mode))
	switch mode {
	case "off", "none", "noop":
		return Hooks{
			Metrics: NoopMetrics{},
			Tracer:  NoopTracer{},
		}
	case "", "log":
		fallthrough
	default:
		return Hooks{
			Metrics: LogMetrics{logger: logger},
			Tracer:  LogTracer{logger: logger},
		}
	}
}

func Ensure(h Hooks) Hooks {
	if h.Metrics == nil {
		h.Metrics = NoopMetrics{}
	}
	if h.Tracer == nil {
		h.Tracer = NoopTracer{}
	}
	return h
}

type LogMetrics struct {
	logger *slog.Logger
}

func (m LogMetrics) Incr(name string, tags map[string]string) {
	if m.logger == nil {
		return
	}
	attrs := []any{
		slog.String("kind", "metric_counter"),
		slog.String("name", name),
	}
	for key, value := range tags {
		attrs = append(attrs, slog.String(key, value))
	}
	m.logger.Info("observability_metric", attrs...)
}

func (m LogMetrics) Observe(name string, value float64, tags map[string]string) {
	if m.logger == nil {
		return
	}
	attrs := []any{
		slog.String("kind", "metric_histogram"),
		slog.String("name", name),
		slog.Float64("value", value),
	}
	for key, v := range tags {
		attrs = append(attrs, slog.String(key, v))
	}
	m.logger.Info("observability_metric", attrs...)
}

type LogTracer struct {
	logger *slog.Logger
}

func (t LogTracer) Start(ctx context.Context, spanName string) (context.Context, func(error)) {
	if t.logger == nil {
		return ctx, func(error) {}
	}
	startedAt := time.Now()
	t.logger.Debug("observability_span_start", slog.String("span", spanName))
	return ctx, func(err error) {
		attrs := []any{
			slog.String("span", spanName),
			slog.Float64("latency_ms", float64(time.Since(startedAt).Microseconds())/1000),
		}
		if err != nil {
			attrs = append(attrs, slog.String("status", "error"), slog.String("error", err.Error()))
		} else {
			attrs = append(attrs, slog.String("status", "ok"))
		}
		t.logger.Debug("observability_span_end", attrs...)
	}
}
