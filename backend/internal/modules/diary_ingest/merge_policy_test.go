package diary_ingest

import "testing"

func TestNormalizeBundleDeterministicOrderAndDedup(t *testing.T) {
	bundle := CanonicalIngestBundle{
		Source:         "Kundelik",
		SourceAccount:  " student ",
		IdempotencyKey: "bundle-key-1234",
		Lessons: []CanonicalLesson{
			{
				SourceLessonKey: "lesson-2",
				Date:            "2026-03-31",
				LessonNumber:    2,
				SubjectName:     "Math",
				Grades: []GradePayload{
					{SourceGradeKey: "g2", Value: "4"},
				},
			},
			{
				SourceLessonKey: "lesson-1",
				Date:            "2026-03-30",
				LessonNumber:    1,
				SubjectName:     "History",
				TopicTitle:      "Topic A",
			},
			{
				SourceLessonKey: "lesson-1",
				Date:            "2026-03-30",
				LessonNumber:    1,
				SubjectName:     "History",
				TopicTitle:      "Topic B",
				Grades: []GradePayload{
					{SourceGradeKey: "g1", Value: "5"},
					{SourceGradeKey: "g1", Value: "5"},
				},
			},
		},
		Attendance: []AttendanceEvent{
			{SourceEventKey: "a2", Date: "2026-03-31", Code: "present"},
			{SourceEventKey: "a1", Date: "2026-03-30", Code: "absent"},
			{SourceEventKey: "a1", Date: "2026-03-30", Code: "absent"},
		},
	}

	out := normalizeBundle(bundle)
	if out.Source != "kundelik" {
		t.Fatalf("expected normalized source, got %s", out.Source)
	}
	if len(out.Lessons) != 2 {
		t.Fatalf("expected 2 deduped lessons, got %d", len(out.Lessons))
	}
	if out.Lessons[0].SourceLessonKey != "lesson-1" {
		t.Fatalf("expected deterministic sorted lessons with lesson-1 first")
	}
	if out.Lessons[0].TopicTitle != "Topic B" {
		t.Fatalf("expected latest non-empty topic to survive merge")
	}
	if len(out.Lessons[0].Grades) != 1 {
		t.Fatalf("expected deduped grades for merged lesson, got %d", len(out.Lessons[0].Grades))
	}
	if len(out.Attendance) != 2 {
		t.Fatalf("expected deduped attendance events, got %d", len(out.Attendance))
	}
}

func TestMergeLessonsPartialUpdateDoesNotOverwriteHomeworkWithEmptyPayload(t *testing.T) {
	base := CanonicalLesson{
		SourceLessonKey: "lesson-1",
		Date:            "2026-03-30",
		LessonNumber:    1,
		Homework: HomeworkPayload{
			SourceHomeworkKey: "hw-1",
			Description:       "Solve 1-10",
			RequiresPhoto:     true,
		},
	}
	incoming := CanonicalLesson{
		SourceLessonKey: "lesson-1",
		Date:            "2026-03-30",
		LessonNumber:    1,
		Homework: HomeworkPayload{
			SourceHomeworkKey: "",
			Description:       "",
			RequiresPhoto:     false,
		},
	}

	merged := mergeLessons(base, incoming)
	if merged.Homework.Description != "Solve 1-10" {
		t.Fatalf("expected existing homework description to remain for partial update")
	}
	if !merged.Homework.RequiresPhoto {
		t.Fatalf("expected existing requires_photo to remain true for partial update")
	}
}

func TestSplitGradesForReconcile(t *testing.T) {
	keyed, keys, unkeyed := splitGradesForReconcile([]GradePayload{
		{SourceGradeKey: "g1", Value: "5"},
		{SourceGradeKey: " g2 ", Value: "4"},
		{SourceGradeKey: "", Value: "A"},
		{SourceGradeKey: "", Value: ""},
	})
	if len(keyed) != 2 {
		t.Fatalf("expected 2 keyed grades, got %d", len(keyed))
	}
	if len(keys) != 2 || keys[0] != "g1" || keys[1] != "g2" {
		t.Fatalf("unexpected keyed set: %#v", keys)
	}
	if len(unkeyed) != 1 {
		t.Fatalf("expected 1 unkeyed grade, got %d", len(unkeyed))
	}
}
