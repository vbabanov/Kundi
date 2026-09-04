package assistant

import (
	"strings"
	"testing"
)

func TestAcademicContextRequiresRepeatedSignals(t *testing.T) {
	if hasPositiveTrend([]string{"positive", "negative"}) {
		t.Fatal("one good result must not be called a positive trend")
	}
	if !hasPositiveTrend([]string{"positive", "positive", "negative"}) {
		t.Fatal("two recent positive results after an older negative should form a trend")
	}
	context := AcademicContext{RecentResults: []string{"Математика: 2"}}
	if len(context.WeakTopics) != 0 {
		t.Fatal("one poor result must not create a weak topic")
	}
}

func TestAcademicContextBoundsAndMatchesHomework(t *testing.T) {
	context := AcademicContext{
		GradeLevel:         7,
		UnfinishedHomework: []ContextHomework{{Subject: "Математика", Description: "Решить задачу про дроби"}},
		RecentTopics:       []string{strings.Repeat("тема", 2_000)},
	}
	if !context.MatchesActiveHomework("Помоги решить задачу про дроби") {
		t.Fatal("real unfinished homework was not matched")
	}
	if len([]rune(context.Render())) > MaxContextRunes {
		t.Fatal("rendered academic context exceeded its bound")
	}
	if len(context.Suggestions()) > 3 {
		t.Fatal("too many suggestions")
	}
}

func TestAcademicContextSuggestionsFollowSessionLocale(t *testing.T) {
	tests := []struct {
		name   string
		locale string
		weak   string
		recent string
		want   []string
	}{
		{"russian Kazakhstan", "ru-KZ", "Дроби", "Проценты", []string{"Разобраться с темой: Дроби", "Повторить: Проценты"}},
		{"kazakh Kazakhstan", "kk-KZ", "Бөлшектер", "Пайыздар", []string{"Тақырыпты түсіну: Бөлшектер", "Қайталау: Пайыздар"}},
	}
	for _, item := range tests {
		t.Run(item.name, func(t *testing.T) {
			got := (AcademicContext{Locale: item.locale, WeakTopics: []string{item.weak}, RecentTopics: []string{item.recent}}).Suggestions()
			if len(got) != len(item.want) {
				t.Fatalf("unexpected suggestions: %#v", got)
			}
			for i := range item.want {
				if got[i] != item.want[i] {
					t.Fatalf("suggestion %d: got %q want %q", i, got[i], item.want[i])
				}
			}
		})
	}

	kkGeneric := (AcademicContext{Locale: "kk"}).Suggestions()
	if len(kkGeneric) != 3 || kkGeneric[0] != "Тақырыпты түсіндір" || kkGeneric[2] != "Жауабымды тексер" {
		t.Fatalf("unexpected Kazakh generic suggestions: %#v", kkGeneric)
	}
}

func TestAcademicContextOptionsUseDocumentedDefaults(t *testing.T) {
	got := (AcademicContextOptions{}).withDefaults()
	want := DefaultAcademicContextOptions()
	if got != want {
		t.Fatalf("unexpected context defaults: got %#v want %#v", got, want)
	}
}
