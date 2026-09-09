package gamification

import (
	"testing"
	"time"
)

func TestCatalogHasExactVersionedRUKKMilestones(t *testing.T) {
	items := Catalog()
	if CatalogVersion != 1 || len(items) != 13 {
		t.Fatalf("catalog version/count = %d/%d, want 1/13", CatalogVersion, len(items))
	}
	wants := map[string]int{
		"activity_first_day": 1, "activity_streak_3": 3, "activity_streak_7": 7, "activity_streak_30": 30,
		"grade_five_1": 1, "grade_five_5": 5, "grade_five_10": 10,
		"learning_question_1": 1, "learning_question_10": 10, "learning_question_50": 50,
		"attempt_check_1": 1, "attempt_check_5": 5, "attempt_check_20": 20,
	}
	for _, item := range items {
		if wants[item.Code] != item.Target {
			t.Fatalf("%s target=%d, want %d", item.Code, item.Target, wants[item.Code])
		}
		category := CategoryTitle(item.Category)
		if item.Title.RU == "" || item.Title.KK == "" || item.Description.RU == "" || item.Description.KK == "" || category.RU == "" || category.KK == "" {
			t.Fatalf("%s has incomplete RU/KK mapping: %#v", item.Code, item)
		}
		delete(wants, item.Code)
	}
	if len(wants) != 0 {
		t.Fatalf("missing catalog entries: %v", wants)
	}
}

func TestStreaksConsecutiveGapAndTodayBoundary(t *testing.T) {
	days := []time.Time{
		time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC),
		time.Date(2026, 9, 2, 0, 0, 0, 0, time.UTC),
		time.Date(2026, 9, 3, 0, 0, 0, 0, time.UTC),
		time.Date(2026, 9, 5, 0, 0, 0, 0, time.UTC),
	}
	current, longest, last := streaks(days, time.Date(2026, 9, 5, 0, 0, 0, 0, time.UTC))
	if current != 1 || longest != 3 || last == nil || last.Day() != 5 {
		t.Fatalf("streak=%d longest=%d last=%v", current, longest, last)
	}
	current, longest, _ = streaks(days, time.Date(2026, 9, 7, 0, 0, 0, 0, time.UTC))
	if current != 0 || longest != 3 {
		t.Fatalf("expired streak=%d longest=%d", current, longest)
	}
}

func TestLevelThresholdsAndNoNegativePoints(t *testing.T) {
	for _, item := range []struct{ points, level, floor, next int }{
		{-10, 1, 0, 100}, {0, 1, 0, 100}, {99, 1, 0, 100}, {100, 2, 100, 250}, {250, 3, 250, 500}, {6000, 10, 5700, 5700},
	} {
		level, floor, next := LevelForPoints(item.points)
		if level != item.level || floor != item.floor || next != item.next {
			t.Fatalf("points=%d got=%d/%d/%d want=%d/%d/%d", item.points, level, floor, next, item.level, item.floor, item.next)
		}
	}
}
