package homeinsight

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
)

const (
	DefaultTimezone        = "Asia/Almaty"
	defaultProviderTimeout = 900 * time.Millisecond
	defaultMaxCacheEntries = 4096
	maxInsightRunes        = 220
)

var ErrLocaleInvalid = errors.New("home insight locale must be ru or kk")

type Clock interface{ Now() time.Time }

type systemClock struct{}

func (systemClock) Now() time.Time { return time.Now() }

type GradeSource interface {
	GradeLevel(ctx context.Context, studentID uuid.UUID) (int, error)
}

type Insight struct {
	Text           string    `json:"text"`
	Kind           Kind      `json:"kind"`
	Locale         string    `json:"locale"`
	ContentID      string    `json:"content_id"`
	CatalogVersion int       `json:"catalog_version"`
	GradeBand      GradeBand `json:"grade_band"`
	Rephrased      bool      `json:"rephrased"`
}

type Options struct {
	Timezone        string
	ProviderTimeout time.Duration
	MaxCacheEntries int
	Clock           Clock
	Catalog         []CatalogItem
}

type Service struct {
	provider        llm.Provider
	grades          GradeSource
	location        *time.Location
	providerTimeout time.Duration
	maxCacheEntries int
	clock           Clock
	catalog         []CatalogItem

	mu    sync.Mutex
	cache map[cacheKey]*cacheEntry
	order []cacheKey
}

type cacheKey struct {
	StudentID uuid.UUID
	Locale    string
	Band      GradeBand
	Day       string
	Slot      string
}

type cacheEntry struct {
	ready   chan struct{}
	insight Insight
}

func NewService(provider llm.Provider, grades GradeSource, options Options) (*Service, error) {
	if grades == nil {
		return nil, errors.New("home insight grade source is required")
	}
	zone := strings.TrimSpace(options.Timezone)
	if zone == "" {
		zone = DefaultTimezone
	}
	location, err := time.LoadLocation(zone)
	if err != nil {
		return nil, fmt.Errorf("load home insight timezone: %w", err)
	}
	timeout := options.ProviderTimeout
	if timeout <= 0 {
		timeout = defaultProviderTimeout
	}
	maxEntries := options.MaxCacheEntries
	if maxEntries <= 0 {
		maxEntries = defaultMaxCacheEntries
	}
	clock := options.Clock
	if clock == nil {
		clock = systemClock{}
	}
	catalog := options.Catalog
	if len(catalog) == 0 {
		catalog = Catalog()
	}
	return &Service{
		provider: provider, grades: grades, location: location,
		providerTimeout: timeout, maxCacheEntries: maxEntries,
		clock: clock, catalog: catalog, cache: make(map[cacheKey]*cacheEntry),
	}, nil
}

func (service *Service) Get(ctx context.Context, studentID uuid.UUID, rawLocale string) (Insight, error) {
	if studentID == uuid.Nil {
		return Insight{}, errors.New("student id is required")
	}
	locale, err := normalizeLocale(rawLocale)
	if err != nil {
		return Insight{}, err
	}
	gradeLevel, err := service.grades.GradeLevel(ctx, studentID)
	if err != nil {
		return Insight{}, fmt.Errorf("load grade level: %w", err)
	}
	band := BandForGrade(gradeLevel)
	day := dateOnly(service.clock.Now().In(service.location))
	key := cacheKey{
		StudentID: studentID, Locale: locale, Band: band,
		Day: day.Format("2006-01-02"), Slot: "daily",
	}
	return service.getOrCompute(ctx, key, day)
}

func (service *Service) getOrCompute(ctx context.Context, key cacheKey, day time.Time) (Insight, error) {
	service.mu.Lock()
	if existing, ok := service.cache[key]; ok {
		ready := existing.ready
		service.mu.Unlock()
		select {
		case <-ready:
			return existing.insight, nil
		case <-ctx.Done():
			return Insight{}, ctx.Err()
		}
	}
	entry := &cacheEntry{ready: make(chan struct{})}
	service.cache[key] = entry
	service.order = append(service.order, key)
	for len(service.order) > service.maxCacheEntries {
		oldest := service.order[0]
		service.order = service.order[1:]
		delete(service.cache, oldest)
	}
	service.mu.Unlock()

	entry.insight = service.compute(ctx, key, day)
	close(entry.ready)
	return entry.insight, nil
}

func (service *Service) compute(ctx context.Context, key cacheKey, day time.Time) Insight {
	item := selectItem(service.catalog, key.StudentID, day, key.Band)
	curated := item.Text.Resolve(key.Locale)
	result := Insight{
		Text: curated, Kind: item.Kind, Locale: key.Locale,
		ContentID: item.ID, CatalogVersion: CatalogVersion, GradeBand: key.Band,
	}
	// Factual entries are immutable. This prevents a model from adding a claim
	// that is not present in the reviewed catalog.
	if item.Kind != KindStudyTip || service.provider == nil {
		return result
	}
	providerContext, cancel := context.WithTimeout(ctx, service.providerTimeout)
	defer cancel()
	response, err := service.provider.Generate(providerContext, llm.Request{
		Mode:        "home_insight_rephrase",
		Prompt:      rephrasePrompt(key.Locale, key.Band, curated),
		PersonaTone: "friendly, calm, age-appropriate",
		Style:       "one or two short sentences; no new facts",
	})
	if err != nil {
		return result
	}
	normalized, ok := validRephrase(response.Text)
	if !ok {
		return result
	}
	result.Text = normalized
	result.Rephrased = normalized != curated
	return result
}

func rephrasePrompt(locale string, band GradeBand, curated string) string {
	language := map[string]string{"ru": "Russian", "kk": "Kazakh"}[locale]
	return fmt.Sprintf(
		"Rewrite only the study tip below in %s for the %s school grade band. Preserve its exact meaning. Do not add facts, names, homework answers, advertising, shame, links, headings, or quotation marks. Return only one or two short sentences, at most %d Unicode characters.\nSTUDY_TIP: %s",
		language, band, maxInsightRunes, curated,
	)
}

var whitespace = regexp.MustCompile(`\s+`)

func validRephrase(raw string) (string, bool) {
	normalized := strings.TrimSpace(whitespace.ReplaceAllString(raw, " "))
	if normalized == "" || utf8.RuneCountInString(normalized) > maxInsightRunes {
		return "", false
	}
	lower := strings.ToLower(normalized)
	for _, blocked := range []string{
		"http://", "https://", "www.", "купи", "реклама", "стыдно",
		"сатып ал", "жарнама", "ұят",
	} {
		if strings.Contains(lower, blocked) {
			return "", false
		}
	}
	sentences := 0
	for _, character := range normalized {
		if character == '.' || character == '!' || character == '?' {
			sentences++
		}
	}
	if sentences > 2 {
		return "", false
	}
	return normalized, true
}

func normalizeLocale(raw string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "ru", "ru-kz", "ru-ru":
		return "ru", nil
	case "kk", "kk-kz":
		return "kk", nil
	default:
		return "", ErrLocaleInvalid
	}
}

func dateOnly(value time.Time) time.Time {
	year, month, day := value.Date()
	return time.Date(year, month, day, 0, 0, 0, 0, value.Location())
}
