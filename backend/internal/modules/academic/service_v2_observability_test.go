package academic

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/kundi/kundi/backend/internal/platform/observability"
)

type metricCall struct {
	name string
	tags map[string]string
}

type readMetricsRecorder struct {
	incr    []metricCall
	observe []metricCall
}

func (m *readMetricsRecorder) Incr(name string, tags map[string]string) {
	m.incr = append(m.incr, metricCall{name: name, tags: cloneTags(tags)})
}

func (m *readMetricsRecorder) Observe(name string, _ float64, tags map[string]string) {
	m.observe = append(m.observe, metricCall{name: name, tags: cloneTags(tags)})
}

type readTracerRecorder struct {
	spans []string
}

func (t *readTracerRecorder) Start(ctx context.Context, spanName string) (context.Context, func(error)) {
	t.spans = append(t.spans, spanName)
	return ctx, func(error) {}
}

type fakeQueryer struct {
	queryRow func(ctx context.Context, sql string, args ...any) pgx.Row
	query    func(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
}

func (f fakeQueryer) Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error) {
	if f.query == nil {
		return nil, errors.New("query function not configured")
	}
	return f.query(ctx, sql, args...)
}

func (f fakeQueryer) QueryRow(ctx context.Context, sql string, args ...any) pgx.Row {
	if f.queryRow == nil {
		return fakeRow{err: errors.New("queryRow function not configured")}
	}
	return f.queryRow(ctx, sql, args...)
}

type fakeRow struct {
	values []any
	err    error
}

func (r fakeRow) Scan(dest ...any) error {
	if r.err != nil {
		return r.err
	}
	if len(dest) != len(r.values) {
		return errors.New("scan destination mismatch")
	}
	for i := range dest {
		switch out := dest[i].(type) {
		case *string:
			*out = r.values[i].(string)
		case *int:
			*out = r.values[i].(int)
		default:
			return errors.New("unsupported scan destination")
		}
	}
	return nil
}

func TestProfileV2EmitsObservabilityAndFallbackSignal(t *testing.T) {
	metrics := &readMetricsRecorder{}
	tracer := &readTracerRecorder{}
	svc := &Service{metrics: metrics, tracer: tracer}
	svc.pool = fakeQueryer{
		queryRow: func(_ context.Context, sql string, _ ...any) pgx.Row {
			switch {
			case strings.Contains(sql, "FROM provider_identity_snapshots"):
				return fakeRow{err: pgx.ErrNoRows}
			case strings.Contains(sql, "FROM student_profiles"):
				return fakeRow{values: []any{"Artem", "Babanov", "10A", "Kundi School"}}
			case strings.Contains(sql, "FROM diary_source_ids"):
				return fakeRow{err: pgx.ErrNoRows}
			case strings.Contains(sql, "FROM diary_accounts"):
				return fakeRow{err: pgx.ErrNoRows}
			case strings.Contains(sql, "FROM student_app_profiles"):
				return fakeRow{err: pgx.ErrNoRows}
			default:
				return fakeRow{err: errors.New("unexpected query")}
			}
		},
		query: func(_ context.Context, _ string, _ ...any) (pgx.Rows, error) {
			return nil, errors.New("unexpected query")
		},
	}

	window := DefaultReadWindowV2("kundelik", time.Now().UTC())
	_, err := svc.ProfileV2(context.Background(), uuid.New(), window)
	if err != nil {
		t.Fatalf("profile v2 failed: %v", err)
	}

	assertMetricWithTag(t, metrics.incr, "backend.read.requests_total", "endpoint", "profile")
	assertMetricWithTag(t, metrics.incr, "backend.read.success_total", "endpoint", "profile")
	assertMetricWithTag(t, metrics.incr, "backend.read.fallback_total", "fallback", "provider_identity_legacy_profile")
	assertMetricWithTag(t, metrics.incr, "backend.read.db_query_total", "query", "provider_identity_snapshot")
	if len(tracer.spans) == 0 {
		t.Fatalf("expected read spans")
	}
}

func TestOverviewV2FailureEmitsFailureMetric(t *testing.T) {
	metrics := &readMetricsRecorder{}
	svc := &Service{metrics: metrics, tracer: observability.NoopTracer{}}
	svc.pool = fakeQueryer{
		queryRow: func(_ context.Context, _ string, _ ...any) pgx.Row {
			return fakeRow{err: errors.New("db down")}
		},
		query: func(_ context.Context, _ string, _ ...any) (pgx.Rows, error) {
			return nil, errors.New("unexpected query")
		},
	}

	window := DefaultReadWindowV2("kundelik", time.Now().UTC())
	_, err := svc.OverviewV2(context.Background(), uuid.New(), window)
	if err == nil {
		t.Fatalf("expected overview error")
	}

	assertMetricWithTag(t, metrics.incr, "backend.read.requests_total", "endpoint", "overview")
	assertMetricWithTag(t, metrics.incr, "backend.read.failure_total", "endpoint", "overview")
}

func TestResultsV2FailureEmitsFailureMetric(t *testing.T) {
	metrics := &readMetricsRecorder{}
	svc := &Service{metrics: metrics, tracer: observability.NoopTracer{}}
	svc.pool = fakeQueryer{
		queryRow: func(_ context.Context, sql string, _ ...any) pgx.Row {
			if strings.Contains(sql, "FROM provider_identity_snapshots") {
				return fakeRow{values: []any{"kundelik", "", "", "", "", "", "", "", ""}}
			}
			return fakeRow{err: errors.New("unexpected row query")}
		},
		query: func(_ context.Context, _ string, _ ...any) (pgx.Rows, error) {
			return nil, errors.New("db down")
		},
	}

	window := DefaultReadWindowV2("kundelik", time.Now().UTC())
	_, err := svc.ResultsV2(context.Background(), uuid.New(), window, 100)
	if err == nil {
		t.Fatalf("expected results error")
	}

	assertMetricWithTag(t, metrics.incr, "backend.read.requests_total", "endpoint", "results")
	assertMetricWithTag(t, metrics.incr, "backend.read.failure_total", "endpoint", "results")
}

func assertMetricWithTag(t *testing.T, calls []metricCall, metricName, tagKey, tagValue string) {
	t.Helper()
	for _, call := range calls {
		if call.name == metricName && call.tags[tagKey] == tagValue {
			return
		}
	}
	t.Fatalf("expected metric %s with %s=%s, got %+v", metricName, tagKey, tagValue, calls)
}

func cloneTags(tags map[string]string) map[string]string {
	if len(tags) == 0 {
		return map[string]string{}
	}
	out := make(map[string]string, len(tags))
	for k, v := range tags {
		out[k] = v
	}
	return out
}
