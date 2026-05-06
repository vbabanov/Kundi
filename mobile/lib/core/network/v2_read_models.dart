class V2Window {
  const V2Window({
    required this.provider,
    required this.windowFrom,
    required this.windowTo,
    required this.snapshotAt,
    required this.windowKey,
  });

  final String provider;
  final String windowFrom;
  final String windowTo;
  final String snapshotAt;
  final String windowKey;

  factory V2Window.fromJson(Map<String, dynamic> json) {
    return V2Window(
      provider: (json['provider'] ?? '').toString(),
      windowFrom: (json['window_from'] ?? '').toString(),
      windowTo: (json['window_to'] ?? '').toString(),
      snapshotAt: (json['snapshot_at'] ?? '').toString(),
      windowKey: (json['window_key'] ?? '').toString(),
    );
  }
}

class V2ProviderIdentity {
  const V2ProviderIdentity({
    required this.provider,
    required this.providerAccountRef,
    required this.providerPersonId,
    required this.providerSchoolId,
    required this.providerGroupId,
    required this.studentFullName,
    required this.schoolName,
    required this.classLabel,
    required this.classTeacherFullName,
  });

  final String provider;
  final String providerAccountRef;
  final String providerPersonId;
  final String providerSchoolId;
  final String providerGroupId;
  final String studentFullName;
  final String schoolName;
  final String classLabel;
  final String classTeacherFullName;

  factory V2ProviderIdentity.fromJson(Map<String, dynamic> json) {
    return V2ProviderIdentity(
      provider: (json['provider'] ?? '').toString(),
      providerAccountRef: (json['provider_account_ref'] ?? '').toString(),
      providerPersonId: (json['provider_person_id'] ?? '').toString(),
      providerSchoolId: (json['provider_school_id'] ?? '').toString(),
      providerGroupId: (json['provider_group_id'] ?? '').toString(),
      studentFullName: (json['student_full_name'] ?? '').toString(),
      schoolName: (json['school_name'] ?? '').toString(),
      classLabel: (json['class_label'] ?? '').toString(),
      classTeacherFullName: (json['class_teacher_full_name'] ?? '').toString(),
    );
  }
}

class V2LocalAppProfile {
  const V2LocalAppProfile({
    required this.shift,
    required this.parentPhone1,
    required this.parentPhone2,
  });

  final int? shift;
  final String parentPhone1;
  final String parentPhone2;

  factory V2LocalAppProfile.fromJson(Map<String, dynamic> json) {
    final parsedShift = int.tryParse((json['shift'] ?? '').toString());
    return V2LocalAppProfile(
      shift: parsedShift,
      parentPhone1: (json['parent_phone_1'] ?? '').toString(),
      parentPhone2: (json['parent_phone_2'] ?? '').toString(),
    );
  }
}

class V2ProfileResponse {
  const V2ProfileResponse({
    required this.window,
    required this.providerIdentity,
    required this.localAppProfile,
  });

  final V2Window window;
  final V2ProviderIdentity providerIdentity;
  final V2LocalAppProfile? localAppProfile;

  factory V2ProfileResponse.fromJson(Map<String, dynamic> json) {
    return V2ProfileResponse(
      window: V2Window.fromJson(_requireMap(json, 'window')),
      providerIdentity:
          V2ProviderIdentity.fromJson(_requireMap(json, 'provider_identity')),
      localAppProfile: _nullableMap(json, 'local_app_profile') == null
          ? null
          : V2LocalAppProfile.fromJson(
              _nullableMap(json, 'local_app_profile')!),
    );
  }
}

class V2LessonItem {
  const V2LessonItem({
    required this.lessonId,
    required this.provider,
    required this.providerLessonId,
    required this.providerSubjectId,
    required this.lessonDate,
    required this.lessonNumber,
    required this.subjectName,
    required this.lessonPlace,
    required this.startTime,
    required this.endTime,
    required this.theme,
    required this.homeworkText,
    required this.homeworkStatus,
  });

  final String lessonId;
  final String provider;
  final String providerLessonId;
  final String providerSubjectId;
  final String lessonDate;
  final int lessonNumber;
  final String subjectName;
  final String lessonPlace;
  final String startTime;
  final String endTime;
  final String theme;
  final String homeworkText;
  final String homeworkStatus;

  factory V2LessonItem.fromJson(Map<String, dynamic> json) {
    return V2LessonItem(
      lessonId: (json['lesson_id'] ?? '').toString(),
      provider: (json['provider'] ?? '').toString(),
      providerLessonId: (json['provider_lesson_id'] ?? '').toString(),
      providerSubjectId: (json['provider_subject_id'] ?? '').toString(),
      lessonDate: (json['lesson_date'] ?? '').toString(),
      lessonNumber: _parseInt(json['lesson_number']),
      subjectName: (json['subject_name'] ?? '').toString(),
      lessonPlace: (json['lesson_place'] ?? '').toString(),
      startTime: (json['start_time'] ?? '').toString(),
      endTime: (json['end_time'] ?? '').toString(),
      theme: (json['theme'] ?? '').toString(),
      homeworkText: (json['homework_text'] ?? '').toString(),
      homeworkStatus: (json['homework_status'] ?? '').toString(),
    );
  }
}

class V2ResultItem {
  const V2ResultItem({
    required this.resultId,
    required this.provider,
    required this.resultKind,
    required this.providerWorkId,
    required this.providerMarkId,
    required this.providerSubjectId,
    required this.subjectName,
    required this.valueText,
    required this.resolvedMood,
    required this.recordedOn,
    required this.sourceEndpoint,
    required this.sourceMoodRaw,
  });

  final String resultId;
  final String provider;
  final String resultKind;
  final String providerWorkId;
  final String providerMarkId;
  final String providerSubjectId;
  final String subjectName;
  final String valueText;
  final String resolvedMood;
  final String recordedOn;
  final String sourceEndpoint;
  final String sourceMoodRaw;

  factory V2ResultItem.fromJson(Map<String, dynamic> json) {
    return V2ResultItem(
      resultId: (json['result_id'] ?? '').toString(),
      provider: (json['provider'] ?? '').toString(),
      resultKind: (json['result_kind'] ?? '').toString(),
      providerWorkId: (json['provider_work_id'] ?? '').toString(),
      providerMarkId: (json['provider_mark_id'] ?? '').toString(),
      providerSubjectId: (json['provider_subject_id'] ?? '').toString(),
      subjectName: (json['subject_name'] ?? '').toString(),
      valueText: (json['value_text'] ?? '').toString(),
      resolvedMood: (json['resolved_mood'] ?? '').toString(),
      recordedOn: (json['recorded_on'] ?? '').toString(),
      sourceEndpoint: (json['source_endpoint'] ?? '').toString(),
      sourceMoodRaw: (json['source_mood_raw'] ?? '').toString(),
    );
  }
}

class V2AggregateItem {
  const V2AggregateItem({
    required this.aggregateId,
    required this.provider,
    required this.resultKind,
    required this.providerSubjectId,
    required this.subjectName,
    required this.valueText,
    required this.resolvedMood,
    required this.recordedOn,
    required this.termNo,
    required this.yearLabel,
  });

  final String aggregateId;
  final String provider;
  final String resultKind;
  final String providerSubjectId;
  final String subjectName;
  final String valueText;
  final String resolvedMood;
  final String recordedOn;
  final int? termNo;
  final String yearLabel;

  factory V2AggregateItem.fromJson(Map<String, dynamic> json) {
    return V2AggregateItem(
      aggregateId: (json['aggregate_id'] ?? '').toString(),
      provider: (json['provider'] ?? '').toString(),
      resultKind: (json['result_kind'] ?? '').toString(),
      providerSubjectId: (json['provider_subject_id'] ?? '').toString(),
      subjectName: (json['subject_name'] ?? '').toString(),
      valueText: (json['value_text'] ?? '').toString(),
      resolvedMood: (json['resolved_mood'] ?? '').toString(),
      recordedOn: (json['recorded_on'] ?? '').toString(),
      termNo: int.tryParse((json['term_no'] ?? '').toString()),
      yearLabel: (json['year_label'] ?? '').toString(),
    );
  }
}

class V2AttendanceItem {
  const V2AttendanceItem({
    required this.attendanceId,
    required this.provider,
    required this.providerEventKey,
    required this.providerLessonRef,
    required this.providerSubjectId,
    required this.subjectName,
    required this.lessonNumber,
    required this.recordedOn,
    required this.rawCode,
    required this.normalizedStatus,
    required this.reason,
  });

  final String attendanceId;
  final String provider;
  final String providerEventKey;
  final String providerLessonRef;
  final String providerSubjectId;
  final String subjectName;
  final int lessonNumber;
  final String recordedOn;
  final String rawCode;
  final String normalizedStatus;
  final String reason;

  factory V2AttendanceItem.fromJson(Map<String, dynamic> json) {
    return V2AttendanceItem(
      attendanceId: (json['attendance_id'] ?? '').toString(),
      provider: (json['provider'] ?? '').toString(),
      providerEventKey: (json['provider_event_key'] ?? '').toString(),
      providerLessonRef: (json['provider_lesson_ref'] ?? '').toString(),
      providerSubjectId: (json['provider_subject_id'] ?? '').toString(),
      subjectName: (json['subject_name'] ?? '').toString(),
      lessonNumber: _parseInt(json['lesson_number']),
      recordedOn: (json['recorded_on'] ?? '').toString(),
      rawCode: (json['raw_code'] ?? '').toString(),
      normalizedStatus: (json['normalized_status'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
    );
  }
}

class V2ResultsResponse {
  const V2ResultsResponse({
    required this.window,
    required this.lessons,
    required this.results,
    required this.aggregates,
    required this.attendance,
  });

  final V2Window window;
  final List<V2LessonItem> lessons;
  final List<V2ResultItem> results;
  final List<V2AggregateItem> aggregates;
  final List<V2AttendanceItem> attendance;

  factory V2ResultsResponse.fromJson(Map<String, dynamic> json) {
    final lessonsRaw = _requireListOfMaps(json, 'lessons');
    final resultsRaw = _requireListOfMaps(json, 'results');
    final aggregatesRaw = _requireListOfMaps(json, 'aggregates');
    final attendanceRaw = _requireListOfMaps(json, 'attendance');
    return V2ResultsResponse(
      window: V2Window.fromJson(_requireMap(json, 'window')),
      lessons: lessonsRaw
          .map((item) => V2LessonItem.fromJson(item))
          .toList(growable: false),
      results: resultsRaw
          .map((item) => V2ResultItem.fromJson(item))
          .toList(growable: false),
      aggregates: aggregatesRaw
          .map((item) => V2AggregateItem.fromJson(item))
          .toList(growable: false),
      attendance: attendanceRaw
          .map((item) => V2AttendanceItem.fromJson(item))
          .toList(growable: false),
    );
  }
}

class V2OverviewCounts {
  const V2OverviewCounts({
    required this.lessonsInWindow,
    required this.resultsInWindow,
    required this.aggregatesInWindow,
    required this.attendanceAlerts,
  });

  final int lessonsInWindow;
  final int resultsInWindow;
  final int aggregatesInWindow;
  final int attendanceAlerts;

  factory V2OverviewCounts.fromJson(Map<String, dynamic> json) {
    return V2OverviewCounts(
      lessonsInWindow: _parseInt(json['lessons_in_window']),
      resultsInWindow: _parseInt(json['results_in_window']),
      aggregatesInWindow: _parseInt(json['aggregates_in_window']),
      attendanceAlerts: _parseInt(json['attendance_alerts']),
    );
  }
}

class V2ResultHighlightItem {
  const V2ResultHighlightItem({
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

  factory V2ResultHighlightItem.fromJson(Map<String, dynamic> json) {
    return V2ResultHighlightItem(
      resultId: (json['result_id'] ?? '').toString(),
      resultKind: (json['result_kind'] ?? '').toString(),
      subjectName: (json['subject_name'] ?? '').toString(),
      valueText: (json['value_text'] ?? '').toString(),
      recordedOn: (json['recorded_on'] ?? '').toString(),
      resolvedMood: (json['resolved_mood'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'result_id': resultId,
      'result_kind': resultKind,
      'subject_name': subjectName,
      'value_text': valueText,
      'recorded_on': recordedOn,
      'resolved_mood': resolvedMood,
    };
  }
}

class V2LessonHighlightItem {
  const V2LessonHighlightItem({
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

  factory V2LessonHighlightItem.fromJson(Map<String, dynamic> json) {
    return V2LessonHighlightItem(
      lessonId: (json['lesson_id'] ?? '').toString(),
      lessonDate: (json['lesson_date'] ?? '').toString(),
      lessonNumber: _parseInt(json['lesson_number']),
      subjectName: (json['subject_name'] ?? '').toString(),
      theme: (json['theme'] ?? '').toString(),
      homeworkText: (json['homework_text'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'lesson_id': lessonId,
      'lesson_date': lessonDate,
      'lesson_number': lessonNumber,
      'subject_name': subjectName,
      'theme': theme,
      'homework_text': homeworkText,
    };
  }
}

class V2OverviewHighlights {
  const V2OverviewHighlights({
    required this.recentResults,
    required this.upcomingLessons,
  });

  final List<V2ResultHighlightItem> recentResults;
  final List<V2LessonHighlightItem> upcomingLessons;

  factory V2OverviewHighlights.fromJson(Map<String, dynamic> json) {
    final recentRaw = _requireListOfMaps(json, 'recent_results');
    final upcomingRaw = _requireListOfMaps(json, 'upcoming_lessons');
    return V2OverviewHighlights(
      recentResults: recentRaw
          .map((item) => V2ResultHighlightItem.fromJson(item))
          .toList(growable: false),
      upcomingLessons: upcomingRaw
          .map((item) => V2LessonHighlightItem.fromJson(item))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'recent_results': recentResults.map((item) => item.toJson()).toList(),
      'upcoming_lessons': upcomingLessons.map((item) => item.toJson()).toList(),
    };
  }
}

class V2OverviewResponse {
  const V2OverviewResponse({
    required this.window,
    required this.providerIdentity,
    required this.localAppProfile,
    required this.counts,
    required this.highlights,
  });

  final V2Window window;
  final V2ProviderIdentity providerIdentity;
  final V2LocalAppProfile? localAppProfile;
  final V2OverviewCounts counts;
  final V2OverviewHighlights highlights;

  Map<String, dynamic> get rawHighlights => highlights.toJson();

  factory V2OverviewResponse.fromJson(Map<String, dynamic> json) {
    return V2OverviewResponse(
      window: V2Window.fromJson(_requireMap(json, 'window')),
      providerIdentity:
          V2ProviderIdentity.fromJson(_requireMap(json, 'provider_identity')),
      localAppProfile: _nullableMap(json, 'local_app_profile') == null
          ? null
          : V2LocalAppProfile.fromJson(
              _nullableMap(json, 'local_app_profile')!),
      counts: V2OverviewCounts.fromJson(_requireMap(json, 'counts')),
      highlights:
          V2OverviewHighlights.fromJson(_requireMap(json, 'highlights')),
    );
  }
}

Map<String, dynamic> _requireMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw const FormatException('v2 dto schema mismatch');
}

Map<String, dynamic>? _nullableMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

List<Map<String, dynamic>> _requireListOfMaps(
  Map<String, dynamic> json,
  String key,
) {
  final raw = json[key];
  if (raw is! List) {
    throw const FormatException('v2 dto schema mismatch');
  }
  return raw.map((item) {
    if (item is! Map) {
      throw const FormatException('v2 dto schema mismatch');
    }
    return Map<String, dynamic>.from(item);
  }).toList(growable: false);
}

int _parseInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse((value ?? '').toString()) ?? 0;
}
