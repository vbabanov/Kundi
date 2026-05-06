import '../../../core/db/canonical_cache_store.dart';
import '../domain/grades_entity.dart';
import '../domain/grades_repository.dart';

class GradesRepositoryImpl implements GradesRepository {
  GradesRepositoryImpl(this._cacheStore);

  final CanonicalCacheStore _cacheStore;

  @override
  Future<GradesScreenData> get() async {
    final context = await _cacheStore.getActiveReadContext();
    if (context != null && context.hasCompleteV2Scope) {
      return _readV2(context);
    }
    return _readLegacy();
  }

  Future<GradesScreenData> _readLegacy() async {
    final rows = await _cacheStore.listGrades();
    final subjectSections = <SubjectSummativeSection>[
      SubjectSummativeSection(
        subjectKey: 'legacy',
        providerSubjectId: '',
        subjectNormalizedName: 'legacy',
        subjectName: 'Legacy grades',
        items: rows
            .map(
              (row) => SummativeItem(
                kind: (row['grade_type'] ?? '').toString().trim().toLowerCase(),
                value: (row['value'] ?? '').toString().trim(),
                mood: (row['mood'] ?? '').toString().trim(),
                recordedOn: (row['created_at'] ?? '').toString().trim(),
                termLabel: '',
              ),
            )
            .toList(growable: false),
      ),
    ];
    return GradesScreenData(
      readMode: 'v1',
      provider: '',
      windowKey: '',
      snapshotAt: '',
      availableWeeks: const <GradesWeekOption>[],
      weeklyRowsByWeek: const <String, List<WeeklySubjectGradesRow>>{},
      latestRegularResults: const <LatestRegularResultItem>[],
      summativeBySubject:
          rows.isEmpty ? const <SubjectSummativeSection>[] : subjectSections,
      aggregatesBySubject: const <SubjectAggregateSection>[],
    );
  }

  Future<GradesScreenData> _readV2(ActiveReadContext context) async {
    final resultsRows = await _cacheStore.listV2Results(context: context);
    final aggregatesRows = await _cacheStore.listV2Aggregates(context: context);
    final lessonsRows = await _cacheStore.listV2Lessons(context: context);
    final attendanceRows = await _cacheStore.listV2Attendance(context: context);

    final lessons = lessonsRows.map(_V2Lesson.fromRow).toList(growable: false);
    final attendance =
        attendanceRows.map(_V2Attendance.fromRow).toList(growable: false);
    final results = resultsRows.map(_V2Result.fromRow).toList(growable: false);
    final aggregates =
        aggregatesRows.map(_V2Aggregate.fromRow).toList(growable: false);
    final summativeSections = _buildSummativeSections(results);

    final weeklyBundle = _buildWeeklyBundle(
      lessons: lessons,
      attendance: attendance,
      results: results,
    );
    return GradesScreenData(
      readMode: 'v2',
      provider: context.provider,
      windowKey: context.windowKey,
      snapshotAt: context.snapshotAt,
      availableWeeks: weeklyBundle.$1,
      weeklyRowsByWeek: weeklyBundle.$2,
      latestRegularResults: _buildLatestRegularResults(results),
      summativeBySubject: summativeSections,
      aggregatesBySubject: _buildAggregateSections(
        aggregates: aggregates,
        summativeSections: summativeSections,
      ),
    );
  }

  List<LatestRegularResultItem> _buildLatestRegularResults(
      List<_V2Result> results) {
    final regular = results
        .where((r) => r.resultKind == 'regular' && r.valueText.isNotEmpty)
        .toList(growable: false);
    final sorted = List<_V2Result>.from(regular)
      ..sort((a, b) => b.recordedOn.compareTo(a.recordedOn));
    return sorted
        .take(40)
        .map(
          (item) => LatestRegularResultItem(
            subjectKey: _subjectKey(item.providerSubjectId, item.subjectName),
            subjectName:
                item.subjectName.isNotEmpty ? item.subjectName : 'Subject',
            value: item.valueText,
            recordedOn: _normalizeYmd(item.recordedOn),
            mood: item.resolvedMood,
          ),
        )
        .toList(growable: false);
  }

  (List<GradesWeekOption>, Map<String, List<WeeklySubjectGradesRow>>)
      _buildWeeklyBundle({
    required List<_V2Lesson> lessons,
    required List<_V2Attendance> attendance,
    required List<_V2Result> results,
  }) {
    final dateSet = <DateTime>{};
    for (final lesson in lessons) {
      final dt = _parseYmd(lesson.lessonDate);
      if (dt != null) {
        dateSet.add(dt);
      }
    }
    for (final result in results.where((r) => r.resultKind == 'regular')) {
      final dt = _parseYmd(result.recordedOn);
      if (dt != null) {
        dateSet.add(dt);
      }
    }
    if (dateSet.isEmpty) {
      return (
        const <GradesWeekOption>[],
        const <String, List<WeeklySubjectGradesRow>>{}
      );
    }

    final sortedDates = dateSet.toList()..sort((a, b) => a.compareTo(b));
    final weekStarts = <DateTime>{};
    for (final dt in sortedDates) {
      weekStarts.add(_startOfWeek(dt));
    }
    final sortedWeeks = weekStarts.toList()..sort((a, b) => a.compareTo(b));

    final options = sortedWeeks
        .map(
          (start) => GradesWeekOption(
            weekKey: _formatYmd(start),
            weekStartDate: _formatYmd(start),
            weekEndDate: _formatYmd(start.add(const Duration(days: 6))),
            label:
                '${_formatShort(start)} - ${_formatShort(start.add(const Duration(days: 6)))}',
          ),
        )
        .toList(growable: false);

    final attendanceByLessonRef = <String, List<_V2Attendance>>{};
    final attendanceByDateSubjectIdLessonNumber =
        <String, List<_V2Attendance>>{};
    final attendanceByDateSubjectNameLessonNumber =
        <String, List<_V2Attendance>>{};
    for (final item in attendance) {
      if (item.providerLessonRef.isEmpty) {
        // Keep processing for fallback keys below.
      } else {
        attendanceByLessonRef
            .putIfAbsent(item.providerLessonRef, () => <_V2Attendance>[])
            .add(item);
      }
      final date = _normalizeYmd(item.recordedOn);
      if (date.isNotEmpty && item.lessonNumber > 0) {
        final subjectId = item.providerSubjectId.trim();
        if (subjectId.isNotEmpty) {
          final key = '$date|$subjectId|${item.lessonNumber}';
          attendanceByDateSubjectIdLessonNumber
              .putIfAbsent(key, () => <_V2Attendance>[])
              .add(item);
        }
        final subjectName = _normalizeSubjectName(item.subjectName);
        if (subjectName.isNotEmpty) {
          final key = '$date|$subjectName|${item.lessonNumber}';
          attendanceByDateSubjectNameLessonNumber
              .putIfAbsent(key, () => <_V2Attendance>[])
              .add(item);
        }
      }
    }

    final regularBySubjectDate = <String, List<String>>{};
    for (final item in results.where((r) => r.resultKind == 'regular')) {
      final date = _normalizeYmd(item.recordedOn);
      if (date.isEmpty) {
        continue;
      }
      final key =
          '${_subjectKey(item.providerSubjectId, item.subjectName)}|$date';
      regularBySubjectDate.putIfAbsent(key, () => <String>[]);
      if (item.valueText.isNotEmpty) {
        regularBySubjectDate[key]!.add(item.valueText);
      }
    }

    final lessonsByDateSubjectIdLessonNumber = <String, List<_V2Lesson>>{};
    final lessonsByDateSubjectNameLessonNumber = <String, List<_V2Lesson>>{};
    for (final lesson in lessons) {
      final date = _normalizeYmd(lesson.lessonDate);
      if (date.isEmpty || lesson.lessonNumber <= 0) {
        continue;
      }
      final subjectId = lesson.providerSubjectId.trim();
      if (subjectId.isNotEmpty) {
        final key = '$date|$subjectId|${lesson.lessonNumber}';
        lessonsByDateSubjectIdLessonNumber
            .putIfAbsent(key, () => <_V2Lesson>[])
            .add(lesson);
      }
      final subjectName = _normalizeSubjectName(lesson.subjectName);
      if (subjectName.isNotEmpty) {
        final key = '$date|$subjectName|${lesson.lessonNumber}';
        lessonsByDateSubjectNameLessonNumber
            .putIfAbsent(key, () => <_V2Lesson>[])
            .add(lesson);
      }
    }

    final rowsByWeek = <String, List<WeeklySubjectGradesRow>>{};
    for (final option in options) {
      final weekStart = _parseYmd(option.weekStartDate)!;
      final weekEnd = weekStart.add(const Duration(days: 6));

      final subjects = <String, _SubjectDraft>{};
      for (final lesson in lessons) {
        final date = _parseYmd(lesson.lessonDate);
        if (date == null || date.isBefore(weekStart) || date.isAfter(weekEnd)) {
          continue;
        }
        final weekday = date.weekday;
        final dayKey = _formatYmd(date);
        final key = _subjectKey(lesson.providerSubjectId, lesson.subjectName);
        final draft = subjects.putIfAbsent(
          key,
          () => _SubjectDraft(
            subjectKey: key,
            subjectName:
                lesson.subjectName.isNotEmpty ? lesson.subjectName : 'Subject',
          ),
        );
        final cell = draft.cells.putIfAbsent(
          weekday,
          () => _CellDraft(date: dayKey),
        );
        cell.hasLesson = true;
        final marksKey = '$key|$dayKey';
        final marks = regularBySubjectDate[marksKey] ?? const <String>[];
        for (final mark in marks) {
          if (mark.isEmpty) {
            continue;
          }
          if (!cell.regularMarks.contains(mark)) {
            cell.regularMarks.add(mark);
          }
        }
        final byRef = attendanceByLessonRef[lesson.providerLessonId] ??
            const <_V2Attendance>[];
        var attendanceForCell = byRef;
        if (attendanceForCell.isEmpty &&
            dayKey.isNotEmpty &&
            lesson.lessonNumber > 0) {
          final lessonSubjectId = lesson.providerSubjectId.trim();
          if (lessonSubjectId.isNotEmpty) {
            final key = '$dayKey|$lessonSubjectId|${lesson.lessonNumber}';
            final byDateSubjectIdNumber =
                attendanceByDateSubjectIdLessonNumber[key] ??
                    const <_V2Attendance>[];
            final lessonCandidates =
                lessonsByDateSubjectIdLessonNumber[key] ?? const <_V2Lesson>[];
            if (byDateSubjectIdNumber.length == 1 &&
                lessonCandidates.length == 1) {
              attendanceForCell = byDateSubjectIdNumber;
            }
          }
          if (attendanceForCell.isEmpty) {
            final lessonSubjectName = _normalizeSubjectName(lesson.subjectName);
            if (lessonSubjectName.isNotEmpty) {
              final key = '$dayKey|$lessonSubjectName|${lesson.lessonNumber}';
              final byDateSubjectNameNumber =
                  attendanceByDateSubjectNameLessonNumber[key] ??
                      const <_V2Attendance>[];
              final lessonCandidates =
                  lessonsByDateSubjectNameLessonNumber[key] ??
                      const <_V2Lesson>[];
              if (byDateSubjectNameNumber.length == 1 &&
                  lessonCandidates.length == 1) {
                attendanceForCell = byDateSubjectNameNumber;
              }
            }
          }
        }
        for (final att in attendanceForCell) {
          if (_normalizeYmd(att.recordedOn) != dayKey) {
            continue;
          }
          final code =
              att.rawCode.isNotEmpty ? att.rawCode : att.normalizedStatus;
          if (code.isEmpty) {
            continue;
          }
          if (!cell.attendanceCodes.contains(code)) {
            cell.attendanceCodes.add(code);
          }
        }
      }

      for (final result in results.where((r) => r.resultKind == 'regular')) {
        final date = _parseYmd(result.recordedOn);
        if (date == null || date.isBefore(weekStart) || date.isAfter(weekEnd)) {
          continue;
        }
        final weekday = date.weekday;
        final dayKey = _formatYmd(date);
        final key = _subjectKey(result.providerSubjectId, result.subjectName);
        final draft = subjects.putIfAbsent(
          key,
          () => _SubjectDraft(
            subjectKey: key,
            subjectName:
                result.subjectName.isNotEmpty ? result.subjectName : 'Subject',
          ),
        );
        final cell = draft.cells.putIfAbsent(
          weekday,
          () => _CellDraft(date: dayKey),
        );
        if (result.valueText.isNotEmpty &&
            !cell.regularMarks.contains(result.valueText)) {
          cell.regularMarks.add(result.valueText);
        }
      }

      final rows = subjects.values
          .map(
            (draft) => WeeklySubjectGradesRow(
              subjectKey: draft.subjectKey,
              subjectName: draft.subjectName,
              cellsByWeekday: Map<int, WeeklyGradeCell>.fromEntries(
                draft.cells.entries.map(
                  (entry) => MapEntry(
                    entry.key,
                    WeeklyGradeCell(
                      date: entry.value.date,
                      hasLesson: entry.value.hasLesson,
                      regularMarks:
                          List<String>.unmodifiable(entry.value.regularMarks),
                      attendanceCodes: List<String>.unmodifiable(
                          entry.value.attendanceCodes),
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => a.subjectName.compareTo(b.subjectName));
      rowsByWeek[option.weekKey] = rows;
    }
    return (options, rowsByWeek);
  }

  List<SubjectSummativeSection> _buildSummativeSections(
      List<_V2Result> results) {
    final bySubject = <String, _SummativeSectionDraft>{};
    for (final item in results
        .where((r) => r.resultKind == 'sor' || r.resultKind == 'soch')) {
      final key = _subjectKey(item.providerSubjectId, item.subjectName);
      final draft = bySubject.putIfAbsent(
        key,
        () => _SummativeSectionDraft(
          subjectKey: key,
          providerSubjectId: item.providerSubjectId.trim(),
          subjectNormalizedName: _normalizeSubjectName(item.subjectName),
          subjectName:
              item.subjectName.isNotEmpty ? item.subjectName : 'Subject',
        ),
      );
      draft.items.add(
        SummativeItem(
          kind: item.resultKind,
          value: item.valueText,
          mood: item.resolvedMood,
          recordedOn: _normalizeYmd(item.recordedOn),
          termLabel: _termLabelFromDate(item.recordedOn),
        ),
      );
    }
    final sections = bySubject.values
        .map(
          (draft) => SubjectSummativeSection(
            subjectKey: draft.subjectKey,
            providerSubjectId: draft.providerSubjectId,
            subjectNormalizedName: draft.subjectNormalizedName,
            subjectName: draft.subjectName,
            items: List<SummativeItem>.from(draft.items)
              ..sort((a, b) => b.recordedOn.compareTo(a.recordedOn)),
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => a.subjectName.compareTo(b.subjectName));
    return sections;
  }

  List<SubjectAggregateSection> _buildAggregateSections({
    required List<_V2Aggregate> aggregates,
    required List<SubjectSummativeSection> summativeSections,
  }) {
    final bySubject = <String, _AggregateSectionDraft>{};
    for (final item in aggregates) {
      final key = _subjectKey(item.providerSubjectId, item.subjectName);
      final draft = bySubject.putIfAbsent(
        key,
        () => _AggregateSectionDraft(
          subjectKey: key,
          providerSubjectId: item.providerSubjectId.trim(),
          subjectNormalizedName: _normalizeSubjectName(item.subjectName),
          subjectName:
              item.subjectName.isNotEmpty ? item.subjectName : 'Subject',
        ),
      );
      final mapped = AggregateItem(
        kind: item.resultKind,
        value: item.valueText,
        mood: item.resolvedMood,
        recordedOn: _normalizeYmd(item.recordedOn),
        termNo: item.termNo,
        yearLabel: item.yearLabel,
      );
      if (item.resultKind == 'year') {
        draft.yearItems.add(mapped);
      } else if (item.resultKind == 'term') {
        draft.termItems.add(mapped);
      }
    }
    final byProviderId = <String, SubjectSummativeSection>{};
    final byNormalized = <String, SubjectSummativeSection>{};
    for (final section in summativeSections) {
      if (section.providerSubjectId.isNotEmpty) {
        byProviderId[section.providerSubjectId] = section;
      }
      if (section.subjectNormalizedName.isNotEmpty) {
        byNormalized[section.subjectNormalizedName] = section;
      }
    }

    final sections = bySubject.values.map(
      (draft) {
        final linkedSummatives = draft.providerSubjectId.isNotEmpty
            ? byProviderId[draft.providerSubjectId]
            : byNormalized[draft.subjectNormalizedName];
        return SubjectAggregateSection(
          subjectKey: draft.subjectKey,
          providerSubjectId: draft.providerSubjectId,
          subjectNormalizedName: draft.subjectNormalizedName,
          subjectName: draft.subjectName,
          termItems: List<AggregateItem>.from(draft.termItems)
            ..sort(
              (a, b) => (a.termNo ?? 0).compareTo(b.termNo ?? 0),
            ),
          yearItems: List<AggregateItem>.from(draft.yearItems)
            ..sort((a, b) => b.recordedOn.compareTo(a.recordedOn)),
          summativeItems: linkedSummatives == null
              ? const <SummativeItem>[]
              : List<SummativeItem>.from(linkedSummatives.items),
        );
      },
    ).toList(growable: false)
      ..sort((a, b) => a.subjectName.compareTo(b.subjectName));
    return sections;
  }

  DateTime? _parseYmd(String raw) {
    final normalized = _normalizeYmd(raw);
    if (normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized);
  }

  String _normalizeYmd(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return '';
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      return text;
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(text)) {
      return text.substring(0, 10);
    }
    return '';
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime.utc(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  String _formatYmd(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatShort(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$d.$m';
  }

  String _subjectKey(String providerSubjectId, String subjectName) {
    final providerKey = providerSubjectId.trim();
    if (providerKey.isNotEmpty) {
      return providerKey;
    }
    final normalized = _normalizeSubjectName(subjectName);
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return 'subject_unknown';
  }

  String _normalizeSubjectName(String value) {
    final lower = value.trim().toLowerCase();
    if (lower.isEmpty) {
      return '';
    }
    return lower.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
  }

  String _termLabelFromDate(String rawDate) {
    final date = _parseYmd(rawDate);
    if (date == null) {
      return 'Unknown term';
    }
    final month = date.month;
    late final int termNo;
    if (month >= 9 && month <= 11) {
      termNo = 1;
    } else if (month == 12 || month == 1 || month == 2) {
      termNo = 2;
    } else if (month == 3 || month == 4) {
      termNo = 3;
    } else {
      termNo = 4;
    }
    return 'Term $termNo';
  }
}

class _V2Lesson {
  const _V2Lesson({
    required this.providerLessonId,
    required this.providerSubjectId,
    required this.lessonDate,
    required this.lessonNumber,
    required this.subjectName,
  });

  final String providerLessonId;
  final String providerSubjectId;
  final String lessonDate;
  final int lessonNumber;
  final String subjectName;

  factory _V2Lesson.fromRow(Map<String, dynamic> row) {
    return _V2Lesson(
      providerLessonId: (row['provider_lesson_id'] ?? '').toString().trim(),
      providerSubjectId: (row['provider_subject_id'] ?? '').toString().trim(),
      lessonDate: (row['lesson_date'] ?? '').toString().trim(),
      lessonNumber: int.tryParse((row['lesson_number'] ?? '').toString()) ?? 0,
      subjectName: (row['subject_name'] ?? '').toString().trim(),
    );
  }
}

class _V2Attendance {
  const _V2Attendance({
    required this.providerLessonRef,
    required this.providerSubjectId,
    required this.subjectName,
    required this.lessonNumber,
    required this.recordedOn,
    required this.rawCode,
    required this.normalizedStatus,
  });

  final String providerLessonRef;
  final String providerSubjectId;
  final String subjectName;
  final int lessonNumber;
  final String recordedOn;
  final String rawCode;
  final String normalizedStatus;

  factory _V2Attendance.fromRow(Map<String, dynamic> row) {
    return _V2Attendance(
      providerLessonRef: (row['provider_lesson_ref'] ?? '').toString().trim(),
      providerSubjectId: (row['provider_subject_id'] ?? '').toString().trim(),
      subjectName: (row['subject_name'] ?? '').toString().trim(),
      lessonNumber: int.tryParse((row['lesson_number'] ?? '').toString()) ?? 0,
      recordedOn: (row['recorded_on'] ?? '').toString().trim(),
      rawCode: (row['raw_code'] ?? '').toString().trim(),
      normalizedStatus: (row['normalized_status'] ?? '').toString().trim(),
    );
  }
}

class _V2Result {
  const _V2Result({
    required this.resultKind,
    required this.providerSubjectId,
    required this.subjectName,
    required this.valueText,
    required this.resolvedMood,
    required this.recordedOn,
  });

  final String resultKind;
  final String providerSubjectId;
  final String subjectName;
  final String valueText;
  final String resolvedMood;
  final String recordedOn;

  factory _V2Result.fromRow(Map<String, dynamic> row) {
    return _V2Result(
      resultKind: (row['result_kind'] ?? '').toString().trim().toLowerCase(),
      providerSubjectId: (row['provider_subject_id'] ?? '').toString().trim(),
      subjectName: (row['subject_name'] ?? '').toString().trim(),
      valueText: (row['value_text'] ?? '').toString().trim(),
      resolvedMood: (row['resolved_mood'] ?? '').toString().trim(),
      recordedOn: (row['recorded_on'] ?? '').toString().trim(),
    );
  }
}

class _V2Aggregate {
  const _V2Aggregate({
    required this.resultKind,
    required this.providerSubjectId,
    required this.subjectName,
    required this.valueText,
    required this.resolvedMood,
    required this.recordedOn,
    required this.termNo,
    required this.yearLabel,
  });

  final String resultKind;
  final String providerSubjectId;
  final String subjectName;
  final String valueText;
  final String resolvedMood;
  final String recordedOn;
  final int? termNo;
  final String yearLabel;

  factory _V2Aggregate.fromRow(Map<String, dynamic> row) {
    return _V2Aggregate(
      resultKind: (row['result_kind'] ?? '').toString().trim().toLowerCase(),
      providerSubjectId: (row['provider_subject_id'] ?? '').toString().trim(),
      subjectName: (row['subject_name'] ?? '').toString().trim(),
      valueText: (row['value_text'] ?? '').toString().trim(),
      resolvedMood: (row['resolved_mood'] ?? '').toString().trim(),
      recordedOn: (row['recorded_on'] ?? '').toString().trim(),
      termNo: int.tryParse((row['term_no'] ?? '').toString()),
      yearLabel: (row['year_label'] ?? '').toString().trim(),
    );
  }
}

class _CellDraft {
  _CellDraft({required this.date});

  final String date;
  bool hasLesson = false;
  final List<String> regularMarks = <String>[];
  final List<String> attendanceCodes = <String>[];
}

class _SubjectDraft {
  _SubjectDraft({
    required this.subjectKey,
    required this.subjectName,
  });

  final String subjectKey;
  final String subjectName;
  final Map<int, _CellDraft> cells = <int, _CellDraft>{};
}

class _SummativeSectionDraft {
  _SummativeSectionDraft({
    required this.subjectKey,
    required this.providerSubjectId,
    required this.subjectNormalizedName,
    required this.subjectName,
  });

  final String subjectKey;
  final String providerSubjectId;
  final String subjectNormalizedName;
  final String subjectName;
  final List<SummativeItem> items = <SummativeItem>[];
}

class _AggregateSectionDraft {
  _AggregateSectionDraft({
    required this.subjectKey,
    required this.providerSubjectId,
    required this.subjectNormalizedName,
    required this.subjectName,
  });

  final String subjectKey;
  final String providerSubjectId;
  final String subjectNormalizedName;
  final String subjectName;
  final List<AggregateItem> termItems = <AggregateItem>[];
  final List<AggregateItem> yearItems = <AggregateItem>[];
}
