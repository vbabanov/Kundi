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
