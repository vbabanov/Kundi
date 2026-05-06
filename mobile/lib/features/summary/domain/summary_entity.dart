class SummaryResultHighlightEntity {
  const SummaryResultHighlightEntity({
    required this.resultId,
    required this.resultKind,
    required this.subjectName,
    required this.valueText,
    required this.recordedOn,
    required this.resolvedMood,
  });

  final String resultId;
  final String resultKind;
  final String subjectName;
  final String valueText;
  final String recordedOn;
  final String resolvedMood;
}

class SummaryLessonHighlightEntity {
  const SummaryLessonHighlightEntity({
    required this.lessonId,
    required this.lessonDate,
    required this.lessonNumber,
    required this.subjectName,
    required this.theme,
    required this.homeworkText,
  });

  final String lessonId;
  final String lessonDate;
  final int lessonNumber;
  final String subjectName;
  final String theme;
  final String homeworkText;
}

class SummaryEntity {
  const SummaryEntity({
    required this.available,
    required this.lessonsCount,
    required this.homeworkCount,
    required this.resultsCount,
    required this.attendanceCount,
    required this.aggregatesCount,
    required this.recentResults,
    required this.upcomingLessons,
  });

  final bool available;
  // Exact semantics:
  // lessonsCount: number of lesson rows in active v2 snapshot scope.
  // homeworkCount: lessonsCount subset with non-empty homework_text.
  // resultsCount: number of event-level results (canonical_results_cache_v2).
  // attendanceCount: number of attendance rows (canonical_attendance_cache_v2).
  final int lessonsCount;
  final int homeworkCount;
  final int resultsCount;
  final int attendanceCount;
  final int aggregatesCount;
  final List<SummaryResultHighlightEntity> recentResults;
  final List<SummaryLessonHighlightEntity> upcomingLessons;

  static const SummaryEntity empty = SummaryEntity(
    available: false,
    lessonsCount: 0,
    homeworkCount: 0,
    resultsCount: 0,
    attendanceCount: 0,
    aggregatesCount: 0,
    recentResults: <SummaryResultHighlightEntity>[],
    upcomingLessons: <SummaryLessonHighlightEntity>[],
  );
}
