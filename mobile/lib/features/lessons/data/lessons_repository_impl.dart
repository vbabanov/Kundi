import '../../../core/db/canonical_cache_store.dart';
import '../domain/lessons_entity.dart';
import '../domain/lessons_repository.dart';

class LessonsRepositoryImpl implements LessonsRepository {
  LessonsRepositoryImpl(this._cacheStore);

  final CanonicalCacheStore _cacheStore;

  @override
  Future<List<LessonsEntity>> list() async {
    final context = await _cacheStore.getActiveReadContext();
    if (context != null && context.hasCompleteV2Scope) {
      return _listFromV2(context);
    }

    final rows = await _cacheStore.listLessons();
    return rows
        .map(
          (row) => LessonsEntity(
            id: (row['lesson_id'] ?? '').toString(),
            date: (row['lesson_date'] ?? '').toString(),
            lessonNumber:
                int.tryParse((row['lesson_number'] ?? '0').toString()) ?? 0,
            lessonPlace: (row['lesson_place'] ?? '').toString().trim(),
            startTime: (row['start_time'] ?? '').toString().trim(),
            endTime: (row['end_time'] ?? '').toString().trim(),
            subjectName: (row['subject_name'] ?? '').toString(),
            topic: (row['topic'] ?? '').toString(),
            homeworkText: (row['homework_text'] ?? '').toString(),
            requiresPhoto: ((row['requires_photo'] ?? 0).toString() == '1'),
            gradeValue: (row['grade_value'] ?? '').toString(),
            attendanceCode: (row['attendance_code'] ?? '').toString(),
          ),
        )
        .toList(growable: false);
  }

  Future<List<LessonsEntity>> _listFromV2(ActiveReadContext context) async {
    final lessonsRows = await _cacheStore.listV2Lessons(context: context);
    final attendanceRows = await _cacheStore.listV2Attendance(context: context);
    final resultRows = await _cacheStore.listV2Results(context: context);

    final attendanceByLessonRef = <String, String>{};
    for (final row in attendanceRows) {
      final lessonRef = (row['provider_lesson_ref'] ?? '').toString().trim();
      if (lessonRef.isEmpty || attendanceByLessonRef.containsKey(lessonRef)) {
        continue;
      }
      final rawCode = (row['raw_code'] ?? '').toString().trim();
      final normalized = (row['normalized_status'] ?? '').toString().trim();
      attendanceByLessonRef[lessonRef] =
          rawCode.isNotEmpty ? rawCode : normalized;
    }

    final regularResults = resultRows
        .where(
          (row) =>
              (row['result_kind'] ?? '').toString().trim().toLowerCase() ==
              'regular',
        )
        .map(_RegularResult.fromRow)
        .where((row) => row.valueText.isNotEmpty && row.recordedOn.isNotEmpty)
        .toList(growable: false);

    final byProviderWorkAndDate = <String, List<_RegularResult>>{};
    final byProviderSubjectAndDate = <String, List<_RegularResult>>{};
    final bySubjectNameAndDate = <String, List<_RegularResult>>{};
    for (final result in regularResults) {
      final normalizedDate = _normalizeYmd(result.recordedOn);
      if (normalizedDate.isEmpty) {
        continue;
      }
      if (result.providerWorkId.isNotEmpty) {
        final key = '${result.providerWorkId}|$normalizedDate';
        byProviderWorkAndDate
            .putIfAbsent(key, () => <_RegularResult>[])
            .add(result);
      }
      if (result.providerSubjectId.isNotEmpty) {
        final key = '${result.providerSubjectId}|$normalizedDate';
        byProviderSubjectAndDate
            .putIfAbsent(key, () => <_RegularResult>[])
            .add(result);
      }
      final normalizedSubject = _normalizeSubjectName(result.subjectName);
      if (normalizedSubject.isNotEmpty) {
        final key = '$normalizedSubject|$normalizedDate';
        bySubjectNameAndDate
            .putIfAbsent(key, () => <_RegularResult>[])
            .add(result);
      }
    }

    return lessonsRows.map((row) {
      final subject = (row['subject_name'] ?? '').toString().trim();
      final date = _normalizeYmd((row['lesson_date'] ?? '').toString());
      final providerLessonId =
          (row['provider_lesson_id'] ?? '').toString().trim();
      final providerSubjectId =
          (row['provider_subject_id'] ?? '').toString().trim();
      final normalizedSubject = _normalizeSubjectName(subject);

      final markValues = _resolveLessonRegularMarks(
        date: date,
        providerLessonId: providerLessonId,
        providerSubjectId: providerSubjectId,
        normalizedSubjectName: normalizedSubject,
        byProviderWorkAndDate: byProviderWorkAndDate,
        byProviderSubjectAndDate: byProviderSubjectAndDate,
        bySubjectNameAndDate: bySubjectNameAndDate,
      );
      final gradeValue = markValues.join(', ');

      return LessonsEntity(
        id: (row['lesson_id'] ?? '').toString(),
        date: date,
        lessonNumber:
            int.tryParse((row['lesson_number'] ?? '0').toString()) ?? 0,
        lessonPlace: (row['lesson_place'] ?? '').toString().trim(),
        startTime: (row['start_time'] ?? '').toString().trim(),
        endTime: (row['end_time'] ?? '').toString().trim(),
        subjectName: subject,
        topic: (row['theme'] ?? '').toString().trim(),
        homeworkText: (row['homework_text'] ?? '').toString().trim(),
        requiresPhoto: false,
        gradeValue: gradeValue,
        attendanceCode: attendanceByLessonRef[providerLessonId] ?? '',
      );
    }).toList(growable: false);
  }

  List<String> _resolveLessonRegularMarks({
    required String date,
    required String providerLessonId,
    required String providerSubjectId,
    required String normalizedSubjectName,
    required Map<String, List<_RegularResult>> byProviderWorkAndDate,
    required Map<String, List<_RegularResult>> byProviderSubjectAndDate,
    required Map<String, List<_RegularResult>> bySubjectNameAndDate,
  }) {
    if (date.isEmpty) {
      return const <String>[];
    }

    List<_RegularResult> matches = <_RegularResult>[];
    // Primary: explicit provider linkage (work/lesson identity).
    if (providerLessonId.isNotEmpty) {
      matches = byProviderWorkAndDate['$providerLessonId|$date'] ??
          const <_RegularResult>[];
    }
    // Fallback: provider subject identity + date.
    if (matches.isEmpty && providerSubjectId.isNotEmpty) {
      matches = byProviderSubjectAndDate['$providerSubjectId|$date'] ??
          const <_RegularResult>[];
    }
    // Weakest fallback: normalized display subject + date, only when identity absent.
    if (matches.isEmpty &&
        providerLessonId.isEmpty &&
        providerSubjectId.isEmpty &&
        normalizedSubjectName.isNotEmpty) {
      matches = bySubjectNameAndDate['$normalizedSubjectName|$date'] ??
          const <_RegularResult>[];
    }

    if (matches.isEmpty) {
      return const <String>[];
    }
    final unique = <String>{};
    for (final match in matches) {
      if (match.valueText.isNotEmpty) {
        unique.add(match.valueText);
      }
    }
    final out = unique.toList(growable: false);
    out.sort();
    return out;
  }

  String _normalizeYmd(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 10 && trimmed[4] == '-' && trimmed[7] == '-') {
      return trimmed.substring(0, 10);
    }
    return '';
  }

  String _normalizeSubjectName(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _RegularResult {
  const _RegularResult({
    required this.providerWorkId,
    required this.providerSubjectId,
    required this.subjectName,
    required this.recordedOn,
    required this.valueText,
  });

  final String providerWorkId;
  final String providerSubjectId;
  final String subjectName;
  final String recordedOn;
  final String valueText;

  factory _RegularResult.fromRow(Map<String, dynamic> row) {
    return _RegularResult(
      providerWorkId: (row['provider_work_id'] ?? '').toString().trim(),
      providerSubjectId: (row['provider_subject_id'] ?? '').toString().trim(),
      subjectName: (row['subject_name'] ?? '').toString().trim(),
      recordedOn: (row['recorded_on'] ?? '').toString().trim(),
      valueText: (row['value_text'] ?? '').toString().trim(),
    );
  }
}
