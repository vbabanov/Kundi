import '../../../core/db/canonical_cache_store.dart';
import '../domain/summary_entity.dart';
import '../domain/summary_repository.dart';

class SummaryRepositoryImpl implements SummaryRepository {
  SummaryRepositoryImpl(this._cacheStore);

  final CanonicalCacheStore _cacheStore;
  static const int _recentResultsLimit = 5;
  static const int _upcomingLessonsLimit = 5;

  @override
  Future<SummaryEntity> get() async {
    final context = await _cacheStore.getActiveReadContext();
    if (context == null || !context.hasCompleteV2Scope) {
      return _readLegacy();
    }

    final lessonsRows = await _cacheStore.listV2Lessons(context: context);
    final resultsRows = await _cacheStore.listV2Results(context: context);
    final attendanceRows = await _cacheStore.listV2Attendance(context: context);
    final aggregatesRows = await _cacheStore.listV2Aggregates(context: context);
    final highlights =
        await _cacheStore.getV2OverviewHighlights(context: context);
    if (lessonsRows.isEmpty &&
        resultsRows.isEmpty &&
        attendanceRows.isEmpty &&
        aggregatesRows.isEmpty &&
        highlights.isEmpty) {
      return SummaryEntity.empty;
    }

    final recentRaw =
        (highlights['recent_results'] as List?) ?? const <dynamic>[];
    final upcomingRaw =
        (highlights['upcoming_lessons'] as List?) ?? const <dynamic>[];
    final recent = recentRaw
        .whereType<Map>()
        .map((raw) => _mapRecentResult(Map<String, dynamic>.from(raw)))
        .whereType<SummaryResultHighlightEntity>()
        .toList(growable: false)
      ..sort((a, b) => b.recordedOn.compareTo(a.recordedOn));
    final upcoming = upcomingRaw
        .whereType<Map>()
        .map((raw) => _mapUpcomingLesson(Map<String, dynamic>.from(raw)))
        .whereType<SummaryLessonHighlightEntity>()
        .toList(growable: false)
      ..sort((a, b) {
        final byDate = a.lessonDate.compareTo(b.lessonDate);
        if (byDate != 0) {
          return byDate;
        }
        return a.lessonNumber.compareTo(b.lessonNumber);
      });

    return SummaryEntity(
      available: true,
      lessonsCount: lessonsRows.length,
      homeworkCount: lessonsRows
          .where(
            (row) => (row['homework_text'] ?? '').toString().trim().isNotEmpty,
          )
          .length,
      resultsCount: resultsRows.length,
      attendanceCount: attendanceRows.length,
      aggregatesCount: aggregatesRows.length,
      recentResults: recent.take(_recentResultsLimit).toList(growable: false),
      upcomingLessons:
          upcoming.take(_upcomingLessonsLimit).toList(growable: false),
    );
  }

  Future<SummaryEntity> _readLegacy() async {
    final lessons = await _cacheStore.listLessons();
    final homework = await _cacheStore.listHomework();
    final grades = await _cacheStore.listGrades();
    if (lessons.isEmpty && homework.isEmpty && grades.isEmpty) {
      return SummaryEntity.empty;
    }

    final recent = grades
        .map(
          (row) => SummaryResultHighlightEntity(
            resultId: (row['grade_id'] ?? '').toString().trim(),
            resultKind: (row['grade_type'] ?? '').toString().trim(),
            subjectName: '',
            valueText: (row['value'] ?? '').toString().trim(),
            recordedOn: _normalizeYmd((row['created_at'] ?? '').toString()),
            resolvedMood: (row['mood'] ?? '').toString().trim(),
          ),
        )
        .where((item) =>
            item.resultId.isNotEmpty &&
            item.valueText.isNotEmpty &&
            item.recordedOn.isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) => b.recordedOn.compareTo(a.recordedOn));

    final upcoming = lessons
        .map(
          (row) => SummaryLessonHighlightEntity(
            lessonId: (row['lesson_id'] ?? '').toString().trim(),
            lessonDate: _normalizeYmd((row['lesson_date'] ?? '').toString()),
            lessonNumber:
                int.tryParse((row['lesson_number'] ?? '0').toString()) ?? 0,
            subjectName: (row['subject_name'] ?? '').toString().trim(),
            theme: (row['topic'] ?? '').toString().trim(),
            homeworkText: (row['homework_text'] ?? '').toString().trim(),
          ),
        )
        .where((item) =>
            item.lessonId.isNotEmpty &&
            item.lessonDate.isNotEmpty &&
            (item.subjectName.isNotEmpty ||
                item.theme.isNotEmpty ||
                item.homeworkText.isNotEmpty))
        .toList(growable: false)
      ..sort((a, b) {
        final byDate = a.lessonDate.compareTo(b.lessonDate);
        if (byDate != 0) {
          return byDate;
        }
        return a.lessonNumber.compareTo(b.lessonNumber);
      });

    return SummaryEntity(
      available: true,
      lessonsCount: lessons.length,
      homeworkCount: homework.length,
      resultsCount: grades.length,
      attendanceCount: 0,
      aggregatesCount: 0,
      recentResults: recent.take(_recentResultsLimit).toList(growable: false),
      upcomingLessons:
          upcoming.take(_upcomingLessonsLimit).toList(growable: false),
    );
  }

  SummaryResultHighlightEntity? _mapRecentResult(Map<String, dynamic> row) {
    final resultId = (row['result_id'] ?? '').toString().trim();
    final valueText = (row['value_text'] ?? '').toString().trim();
    final recordedOn = _normalizeYmd((row['recorded_on'] ?? '').toString());
    if (resultId.isEmpty || valueText.isEmpty || recordedOn.isEmpty) {
      return null;
    }
    return SummaryResultHighlightEntity(
      resultId: resultId,
      resultKind: (row['result_kind'] ?? '').toString().trim(),
      subjectName: (row['subject_name'] ?? '').toString().trim(),
      valueText: valueText,
      recordedOn: recordedOn,
      resolvedMood: (row['resolved_mood'] ?? '').toString().trim(),
    );
  }

  SummaryLessonHighlightEntity? _mapUpcomingLesson(Map<String, dynamic> row) {
    final lessonId = (row['lesson_id'] ?? '').toString().trim();
    final lessonDate = _normalizeYmd((row['lesson_date'] ?? '').toString());
    final subjectName = (row['subject_name'] ?? '').toString().trim();
    final theme = (row['theme'] ?? '').toString().trim();
    final homeworkText = (row['homework_text'] ?? '').toString().trim();
    if (lessonId.isEmpty || lessonDate.isEmpty) {
      return null;
    }
    if (subjectName.isEmpty && theme.isEmpty && homeworkText.isEmpty) {
      return null;
    }
    final status =
        (row['homework_status'] ?? '').toString().trim().toLowerCase();
    if (status == 'canceled' || status == 'cancelled') {
      return null;
    }
    final today = DateTime.now().toUtc();
    final todayYmd = DateTime.utc(today.year, today.month, today.day);
    final lessonYmd = _parseYmd(lessonDate);
    if (lessonYmd == null || !lessonYmd.isAfter(todayYmd)) {
      return null;
    }
    return SummaryLessonHighlightEntity(
      lessonId: lessonId,
      lessonDate: lessonDate,
      lessonNumber: int.tryParse((row['lesson_number'] ?? '0').toString()) ?? 0,
      subjectName: subjectName,
      theme: theme,
      homeworkText: homeworkText,
    );
  }

  DateTime? _parseYmd(String value) {
    final normalized = _normalizeYmd(value);
    if (normalized.isEmpty) {
      return null;
    }
    final parts = normalized.split('-');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime.utc(year, month, day);
  }

  String _normalizeYmd(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.length >= 10 && trimmed[4] == '-' && trimmed[7] == '-') {
      return trimmed.substring(0, 10);
    }
    return '';
  }
}
