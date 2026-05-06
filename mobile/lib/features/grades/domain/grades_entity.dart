class GradesScreenData {
  const GradesScreenData({
    required this.readMode,
    required this.provider,
    required this.windowKey,
    required this.snapshotAt,
    required this.availableWeeks,
    required this.weeklyRowsByWeek,
    required this.latestRegularResults,
    required this.summativeBySubject,
    required this.aggregatesBySubject,
  });

  final String readMode;
  final String provider;
  final String windowKey;
  final String snapshotAt;
  final List<GradesWeekOption> availableWeeks;
  final Map<String, List<WeeklySubjectGradesRow>> weeklyRowsByWeek;
  final List<LatestRegularResultItem> latestRegularResults;
  final List<SubjectSummativeSection> summativeBySubject;
  final List<SubjectAggregateSection> aggregatesBySubject;

  bool get isV2 => readMode == 'v2';

  bool get isEmpty =>
      weeklyRowsByWeek.values.every((rows) => rows.isEmpty) &&
      latestRegularResults.isEmpty &&
      summativeBySubject.isEmpty &&
      aggregatesBySubject.isEmpty;
}

class LatestRegularResultItem {
  const LatestRegularResultItem({
    required this.subjectKey,
    required this.subjectName,
    required this.value,
    required this.recordedOn,
    required this.mood,
  });

  final String subjectKey;
  final String subjectName;
  final String value;
  final String recordedOn;
  final String mood;
}

class GradesWeekOption {
  const GradesWeekOption({
    required this.weekKey,
    required this.weekStartDate,
    required this.weekEndDate,
    required this.label,
  });

  final String weekKey;
  final String weekStartDate;
  final String weekEndDate;
  final String label;
}

class WeeklySubjectGradesRow {
  const WeeklySubjectGradesRow({
    required this.subjectKey,
    required this.subjectName,
    required this.cellsByWeekday,
  });

  final String subjectKey;
  final String subjectName;
  final Map<int, WeeklyGradeCell> cellsByWeekday;
}

class WeeklyGradeCell {
  const WeeklyGradeCell({
    required this.date,
    required this.hasLesson,
    required this.regularMarks,
    required this.attendanceCodes,
  });

  final String date;
  final bool hasLesson;
  final List<String> regularMarks;
  final List<String> attendanceCodes;

  bool get hasMark => regularMarks.isNotEmpty;

  bool get hasAttendance => attendanceCodes.isNotEmpty;

  bool get showDot => hasLesson && !hasMark && !hasAttendance;
}

class SubjectSummativeSection {
  const SubjectSummativeSection({
    required this.subjectKey,
    required this.providerSubjectId,
    required this.subjectNormalizedName,
    required this.subjectName,
    required this.items,
  });

  final String subjectKey;
  final String providerSubjectId;
  final String subjectNormalizedName;
  final String subjectName;
  final List<SummativeItem> items;
}

class SummativeItem {
  const SummativeItem({
    required this.kind,
    required this.value,
    required this.mood,
    required this.recordedOn,
    required this.termLabel,
  });

  final String kind;
  final String value;
  final String mood;
  final String recordedOn;
  final String termLabel;
}

class SubjectAggregateSection {
  const SubjectAggregateSection({
    required this.subjectKey,
    required this.providerSubjectId,
    required this.subjectNormalizedName,
    required this.subjectName,
    required this.termItems,
    required this.yearItems,
    required this.summativeItems,
  });

  final String subjectKey;
  final String providerSubjectId;
  final String subjectNormalizedName;
  final String subjectName;
  final List<AggregateItem> termItems;
  final List<AggregateItem> yearItems;
  final List<SummativeItem> summativeItems;
}

class AggregateItem {
  const AggregateItem({
    required this.kind,
    required this.value,
    required this.mood,
    required this.recordedOn,
    required this.termNo,
    required this.yearLabel,
  });

  final String kind;
  final String value;
  final String mood;
  final String recordedOn;
  final int? termNo;
  final String yearLabel;
}
