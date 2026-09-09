package homeinsight

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
)

type fixedClock struct{ value time.Time }

func (clock fixedClock) Now() time.Time { return clock.value }

type fixedGradeSource struct{ grade int }

func (source fixedGradeSource) GradeLevel(context.Context, uuid.UUID) (int, error) {
	return source.grade, nil
}

type recordingProvider struct {
	mu       sync.Mutex
	response string
	err      error
	wait     bool
	requests []llm.Request
}

func (provider *recordingProvider) Generate(ctx context.Context, request llm.Request) (llm.Response, error) {
	provider.mu.Lock()
	provider.requests = append(provider.requests, request)
	provider.mu.Unlock()
	if provider.wait {
		<-ctx.Done()
		return llm.Response{}, ctx.Err()
	}
	return llm.Response{Text: provider.response}, provider.err
}

func (provider *recordingProvider) calls() int {
	provider.mu.Lock()
	defer provider.mu.Unlock()
	return len(provider.requests)
}

func studyTipCatalog() []CatalogItem {
	return []CatalogItem{{
		ID: "test_tip", Kind: KindStudyTip,
		Bands: []GradeBand{GradeBandPrimary, GradeBandMiddle, GradeBandSenior},
		Text:  LocalizedText{RU: "Проверь первый шаг.", KK: "Бірінші қадамды тексер."},
	}}
}

func factCatalog() []CatalogItem {
	return []CatalogItem{{
		ID: "test_fact", Kind: KindDidYouKnow, EvidenceID: "test-evidence",
		Bands: []GradeBand{GradeBandPrimary, GradeBandMiddle, GradeBandSenior},
		Text:  LocalizedText{RU: "Проверенный факт.", KK: "Тексерілген дерек."},
	}}
}

func newTestService(t *testing.T, provider llm.Provider, grade int, catalog []CatalogItem, timeout time.Duration) *Service {
	t.Helper()
	service, err := NewService(provider, fixedGradeSource{grade: grade}, Options{
		Timezone: "UTC", ProviderTimeout: timeout, Catalog: catalog,
		Clock: fixedClock{value: time.Date(2026, 9, 9, 12, 0, 0, 0, time.UTC)},
	})
	if err != nil {
		t.Fatal(err)
	}
	return service
}

func TestGetCachesDailyLocalizedResult(t *testing.T) {
	provider := &recordingProvider{response: "Сначала проверь первый шаг."}
	service := newTestService(t, provider, 3, studyTipCatalog(), time.Second)
	studentID := uuid.New()

	first, err := service.Get(context.Background(), studentID, "ru-KZ")
	if err != nil {
		t.Fatal(err)
	}
	second, err := service.Get(context.Background(), studentID, "ru")
	if err != nil {
		t.Fatal(err)
	}
	if first != second {
		t.Fatalf("cached result changed: first=%+v second=%+v", first, second)
	}
	if provider.calls() != 1 {
		t.Fatalf("provider calls=%d want=1", provider.calls())
	}
	if !first.Rephrased || first.GradeBand != GradeBandPrimary || first.Locale != "ru" {
		t.Fatalf("unexpected result: %+v", first)
	}
	provider.mu.Lock()
	prompt := provider.requests[0].Prompt
	provider.mu.Unlock()
	if strings.Contains(prompt, studentID.String()) {
		t.Fatal("provider prompt contains student id")
	}
}

func TestGetCoalescesConcurrentProviderRequests(t *testing.T) {
	provider := &recordingProvider{response: "Проверь первый шаг ещё раз."}
	service := newTestService(t, provider, 6, studyTipCatalog(), time.Second)
	studentID := uuid.New()
	start := make(chan struct{})
	results := make(chan Insight, 12)
	errors := make(chan error, 12)
	var wait sync.WaitGroup
	for range 12 {
		wait.Add(1)
		go func() {
			defer wait.Done()
			<-start
			insight, err := service.Get(context.Background(), studentID, "ru")
			results <- insight
			errors <- err
		}()
	}
	close(start)
	wait.Wait()
	close(results)
	close(errors)
	for err := range errors {
		if err != nil {
			t.Fatal(err)
		}
	}
	for insight := range results {
		if insight.Text != "Проверь первый шаг ещё раз." {
			t.Fatalf("unexpected result: %+v", insight)
		}
	}
	if provider.calls() != 1 {
		t.Fatalf("provider calls=%d want=1", provider.calls())
	}
}

func TestGetReturnsKazakhAndNeverRephrasesFacts(t *testing.T) {
	provider := &recordingProvider{response: "Модельден шыққан мәтін."}
	service := newTestService(t, provider, 8, factCatalog(), time.Second)

	insight, err := service.Get(context.Background(), uuid.New(), "kk-KZ")
	if err != nil {
		t.Fatal(err)
	}
	if insight.Text != "Тексерілген дерек." || insight.Locale != "kk" || insight.Kind != KindDidYouKnow || insight.Rephrased {
		t.Fatalf("unexpected result: %+v", insight)
	}
	if provider.calls() != 0 {
		t.Fatalf("factual entry reached provider %d times", provider.calls())
	}
}

func TestGetFallsBackToCuratedTipOnProviderFailureOrUnsafeOutput(t *testing.T) {
	tests := []struct {
		name     string
		provider *recordingProvider
		timeout  time.Duration
	}{
		{name: "error", provider: &recordingProvider{err: errors.New("offline")}, timeout: time.Second},
		{name: "unsafe link", provider: &recordingProvider{response: "Купи курс: https://example.com"}, timeout: time.Second},
		{name: "too long", provider: &recordingProvider{response: strings.Repeat("я", maxInsightRunes+1)}, timeout: time.Second},
		{name: "timeout", provider: &recordingProvider{wait: true}, timeout: 5 * time.Millisecond},
	}
	for _, testCase := range tests {
		t.Run(testCase.name, func(t *testing.T) {
			service := newTestService(t, testCase.provider, 10, studyTipCatalog(), testCase.timeout)
			insight, err := service.Get(context.Background(), uuid.New(), "ru")
			if err != nil {
				t.Fatal(err)
			}
			if insight.Text != "Проверь первый шаг." || insight.Rephrased {
				t.Fatalf("expected curated fallback, got %+v", insight)
			}
		})
	}
}

func TestGetRejectsUnsupportedLocale(t *testing.T) {
	service := newTestService(t, nil, 5, studyTipCatalog(), time.Second)
	_, err := service.Get(context.Background(), uuid.New(), "en")
	if !errors.Is(err, ErrLocaleInvalid) {
		t.Fatalf("error=%v want ErrLocaleInvalid", err)
	}
}
