package homeinsight

import (
	"testing"
	"unicode/utf8"
)

func TestCatalogIsLocalizedBoundedAndAuditable(t *testing.T) {
	seen := make(map[string]struct{})
	for _, item := range Catalog() {
		if item.ID == "" {
			t.Fatal("catalog item has an empty id")
		}
		if _, exists := seen[item.ID]; exists {
			t.Fatalf("duplicate catalog id %q", item.ID)
		}
		seen[item.ID] = struct{}{}
		if item.Kind != KindStudyTip && item.Kind != KindDidYouKnow {
			t.Fatalf("item %q has unsupported kind %q", item.ID, item.Kind)
		}
		if len(item.Bands) == 0 {
			t.Fatalf("item %q has no grade band", item.ID)
		}
		if item.Kind == KindDidYouKnow && item.EvidenceID == "" {
			t.Fatalf("factual item %q has no evidence id", item.ID)
		}
		for _, locale := range []string{"ru", "kk"} {
			value := item.Text.Resolve(locale)
			if value == "" {
				t.Fatalf("item %q has empty %s copy", item.ID, locale)
			}
			if utf8.RuneCountInString(value) > maxInsightRunes {
				t.Fatalf("item %q %s copy is too long", item.ID, locale)
			}
			if _, ok := validRephrase(value); !ok {
				t.Fatalf("item %q %s copy violates presentation limits", item.ID, locale)
			}
		}
	}
}

func TestBandForGrade(t *testing.T) {
	tests := map[int]GradeBand{
		1: GradeBandPrimary, 4: GradeBandPrimary,
		5: GradeBandMiddle, 8: GradeBandMiddle,
		9: GradeBandSenior, 12: GradeBandSenior,
	}
	for grade, want := range tests {
		if got := BandForGrade(grade); got != want {
			t.Fatalf("grade %d: got %q want %q", grade, got, want)
		}
	}
}
