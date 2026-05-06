class DiaryAuthCredentials {
  const DiaryAuthCredentials({
    required this.source,
    required this.login,
    required this.password,
  });

  final String source;
  final String login;
  final String password;
}

class DiarySyncRequest {
  const DiarySyncRequest({
    required this.idempotencyKey,
    required this.from,
    required this.to,
  });

  final String idempotencyKey;
  final DateTime from;
  final DateTime to;
}

class SourceProfile {
  const SourceProfile({
    required this.firstName,
    required this.lastName,
    required this.gradeLevel,
    required this.classLabel,
    required this.schoolName,
    required this.classTeacherFullName,
  });

  final String firstName;
  final String lastName;
  final int gradeLevel;
  final String classLabel;
  final String schoolName;
  final String classTeacherFullName;

  String get studentFullName {
    final full = '$firstName $lastName'.trim();
    return full;
  }
}

class SourceLesson {
  const SourceLesson({
    required this.sourceLessonKey,
    required this.date,
    required this.lessonNumber,
    required this.subjectName,
    required this.lessonPlace,
    required this.startTime,
    required this.endTime,
    required this.topicTitle,
    required this.homeworkText,
    required this.requiresPhoto,
    required this.grades,
  });

  final String sourceLessonKey;
  final String date;
  final int lessonNumber;
  final String subjectName;
  final String lessonPlace;
  final String startTime;
  final String endTime;
  final String topicTitle;
  final String homeworkText;
  final bool requiresPhoto;
  final List<SourceGrade> grades;
}

class SourceGrade {
  const SourceGrade({
    required this.sourceGradeKey,
    required this.value,
    required this.mood,
    required this.type,
    required this.isAbsent,
  });

  final String sourceGradeKey;
  final String value;
  final String mood;
  final String type;
  final bool isAbsent;
}

class SourceAcademicResult {
  const SourceAcademicResult({
    required this.sourceResultKey,
    required this.resultKind,
    required this.providerWorkId,
    required this.providerMarkId,
    required this.providerSubjectId,
    required this.subjectName,
    required this.lessonRefKey,
    required this.recordedOn,
    required this.periodId,
    required this.termNo,
    required this.valueText,
    required this.valueNumeric,
    required this.resolvedMood,
    required this.sourceEndpoint,
    required this.sourceMoodRaw,
  });

  final String sourceResultKey;
  final String resultKind;
  final String providerWorkId;
  final String providerMarkId;
  final String providerSubjectId;
  final String subjectName;
  final String lessonRefKey;
  final String recordedOn;
  final String periodId;
  final int? termNo;
  final String valueText;
  final double? valueNumeric;
  final String resolvedMood;
  final String sourceEndpoint;
  final String sourceMoodRaw;
}

class SourceAcademicAggregate {
  const SourceAcademicAggregate({
    required this.sourceAggregateKey,
    required this.resultKind,
    required this.providerSubjectId,
    required this.subjectName,
    required this.recordedOn,
    required this.periodId,
    required this.termNo,
    required this.yearLabel,
    required this.valueText,
    required this.valueNumeric,
    required this.resolvedMood,
    required this.sourceEndpoint,
    required this.sourceMoodRaw,
  });

  final String sourceAggregateKey;
  final String resultKind;
  final String providerSubjectId;
  final String subjectName;
  final String recordedOn;
  final String periodId;
  final int? termNo;
  final String yearLabel;
  final String valueText;
  final double? valueNumeric;
  final String resolvedMood;
  final String sourceEndpoint;
  final String sourceMoodRaw;
}

class SourceResultEvidence {
  const SourceResultEvidence({
    required this.sourceResultRefKey,
    required this.sourceAggregateRefKey,
    required this.sourceEndpoint,
    required this.providerWorkId,
    required this.providerMarkId,
    required this.providerPayloadPath,
    required this.sourceMoodRaw,
    required this.fingerprintSha256,
  });

  final String sourceResultRefKey;
  final String sourceAggregateRefKey;
  final String sourceEndpoint;
  final String providerWorkId;
  final String providerMarkId;
  final String providerPayloadPath;
  final String sourceMoodRaw;
  final String fingerprintSha256;
}

class SourceAttendanceEvent {
  const SourceAttendanceEvent({
    required this.sourceEventKey,
    required this.date,
    required this.code,
    required this.reason,
    this.providerEventKey = '',
    this.providerLessonRef = '',
    this.providerSubjectId = '',
    this.subjectName = '',
    this.lessonNumber = 0,
    this.normalizedStatus = 'unknown',
  });

  final String sourceEventKey;
  final String date;
  final String code;
  final String reason;
  final String providerEventKey;
  final String providerLessonRef;
  final String providerSubjectId;
  final String subjectName;
  final int lessonNumber;
  final String normalizedStatus;

  SourceAttendanceEvent copyWith({
    String? sourceEventKey,
    String? date,
    String? code,
    String? reason,
    String? providerEventKey,
    String? providerLessonRef,
    String? providerSubjectId,
    String? subjectName,
    int? lessonNumber,
    String? normalizedStatus,
  }) {
    return SourceAttendanceEvent(
      sourceEventKey: sourceEventKey ?? this.sourceEventKey,
      date: date ?? this.date,
      code: code ?? this.code,
      reason: reason ?? this.reason,
      providerEventKey: providerEventKey ?? this.providerEventKey,
      providerLessonRef: providerLessonRef ?? this.providerLessonRef,
      providerSubjectId: providerSubjectId ?? this.providerSubjectId,
      subjectName: subjectName ?? this.subjectName,
      lessonNumber: lessonNumber ?? this.lessonNumber,
      normalizedStatus: normalizedStatus ?? this.normalizedStatus,
    );
  }
}

class SourceLocalAppProfile {
  const SourceLocalAppProfile({
    required this.shift,
    required this.parentPhone1,
    required this.parentPhone2,
  });

  final int? shift;
  final String parentPhone1;
  final String parentPhone2;
}

class CanonicalBundle {
  const CanonicalBundle({
    required this.source,
    required this.sourceAccount,
    required this.idempotencyKey,
    required this.syncedAt,
    required this.sourceIds,
    required this.profile,
    required this.lessons,
    required this.attendance,
    this.results = const <SourceAcademicResult>[],
    this.aggregates = const <SourceAcademicAggregate>[],
    this.evidence = const <SourceResultEvidence>[],
    this.localAppProfile,
  });

  final String source;
  final String sourceAccount;
  final String idempotencyKey;
  final DateTime syncedAt;
  final Map<String, String> sourceIds;
  final SourceProfile profile;
  final List<SourceLesson> lessons;
  final List<SourceAttendanceEvent> attendance;
  final List<SourceAcademicResult> results;
  final List<SourceAcademicAggregate> aggregates;
  final List<SourceResultEvidence> evidence;
  final SourceLocalAppProfile? localAppProfile;

  Map<String, dynamic> toJson() {
    return toV1Json();
  }

  Map<String, dynamic> toV1Json() {
    return {
      'source': source,
      'source_account': sourceAccount,
      'idempotency_key': idempotencyKey,
      'synced_at': syncedAt.toUtc().toIso8601String(),
      'source_ids': sourceIds,
      'profile': {
        'first_name': profile.firstName,
        'last_name': profile.lastName,
        'grade_level': profile.gradeLevel,
        'class_label': profile.classLabel,
        'school_name': profile.schoolName,
      },
      'lessons': lessons
          .map(
            (lesson) => {
              'source_lesson_key': lesson.sourceLessonKey,
              'date': _normalizeLessonDate(lesson.date),
              'lesson_number': _normalizeLessonNumberForIngest(
                lesson.lessonNumber,
              ),
              'subject_name': lesson.subjectName,
              'lesson_place': lesson.lessonPlace,
              'start_time': _normalizeLessonTime(lesson.startTime),
              'end_time': _normalizeLessonTime(lesson.endTime),
              'topic_title': lesson.topicTitle,
              'homework': {
                'source_homework_key': '',
                'description': lesson.homeworkText,
                'requires_photo': lesson.requiresPhoto,
              },
              'grades': lesson.grades
                  .map(
                    (grade) => {
                      'source_grade_key': grade.sourceGradeKey,
                      'value': grade.value,
                      'mood': grade.mood,
                      'type': grade.type,
                      'is_absent': grade.isAbsent,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
      'attendance': attendance
          .map(
            (event) => {
              'source_event_key': event.sourceEventKey,
              'date': event.date,
              'code': event.code,
              'reason': event.reason,
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> toV2Json() {
    return {
      'contract_version': 2,
      'source': source,
      'source_account': sourceAccount,
      'idempotency_key': idempotencyKey,
      'synced_at': syncedAt.toUtc().toIso8601String(),
      'identity': {
        'provider': source,
        'provider_account_ref': sourceAccount,
        'provider_person_id': sourceIds['person_id'] ?? '',
        'provider_school_id': sourceIds['school_id'] ?? '',
        'provider_group_id': sourceIds['group_id'] ?? '',
        'student_full_name': profile.studentFullName,
        'school_name': profile.schoolName,
        'class_label': profile.classLabel,
        'class_teacher_full_name': profile.classTeacherFullName,
      },
      'lessons': lessons
          .map(
            (lesson) => {
              'source_lesson_key': lesson.sourceLessonKey,
              'provider_lesson_id': lesson.sourceLessonKey,
              'provider_subject_id': '',
              'date': _normalizeLessonDate(lesson.date),
              'lesson_number': _normalizeLessonNumberForIngest(
                lesson.lessonNumber,
              ),
              'subject_name': lesson.subjectName,
              'lesson_place': lesson.lessonPlace,
              'start_time': _normalizeLessonTime(lesson.startTime),
              'end_time': _normalizeLessonTime(lesson.endTime),
              'theme': lesson.topicTitle,
              'homework_text': lesson.homeworkText,
              'requires_photo': lesson.requiresPhoto,
            },
          )
          .toList(growable: false),
      'results': results
          .map(
            (item) => {
              'source_result_key': item.sourceResultKey,
              'result_kind': item.resultKind,
              'provider_work_id': item.providerWorkId,
              'provider_mark_id': item.providerMarkId,
              'provider_subject_id': item.providerSubjectId,
              'subject_name': item.subjectName,
              'lesson_ref_key': item.lessonRefKey,
              'recorded_on': _normalizeLessonDate(item.recordedOn),
              'period_id': item.periodId,
              'term_no': item.termNo,
              'value_text': item.valueText,
              'value_numeric': item.valueNumeric,
              'resolved_mood': item.resolvedMood,
            },
          )
          .toList(growable: false),
      'aggregates': aggregates
          .map(
            (item) => {
              'source_aggregate_key': item.sourceAggregateKey,
              'result_kind': item.resultKind,
              'provider_subject_id': item.providerSubjectId,
              'subject_name': item.subjectName,
              'recorded_on': _normalizeLessonDate(item.recordedOn),
              'period_id': item.periodId,
              'term_no': item.termNo,
              'year_label': item.yearLabel,
              'value_text': item.valueText,
              'value_numeric': item.valueNumeric,
              'resolved_mood': item.resolvedMood,
            },
          )
          .toList(growable: false),
      'attendance': attendance
          .map(
            (item) => {
              'source_event_key': item.sourceEventKey,
              'provider_event_key': item.providerEventKey,
              'provider_lesson_ref': item.providerLessonRef,
              'provider_subject_id': item.providerSubjectId,
              'subject_name': item.subjectName,
              'lesson_number': _normalizeLessonNumberForIngest(
                item.lessonNumber,
              ),
              'recorded_on': _normalizeLessonDate(item.date),
              'raw_code': item.code,
              'normalized_status': item.normalizedStatus,
              'reason': item.reason,
            },
          )
          .toList(growable: false),
      'evidence': evidence
          .map(
            (item) => {
              'source_result_ref_key': item.sourceResultRefKey,
              'source_aggregate_ref_key': item.sourceAggregateRefKey,
              'source_endpoint': item.sourceEndpoint,
              'provider_work_id': item.providerWorkId,
              'provider_mark_id': item.providerMarkId,
              'provider_payload_path': item.providerPayloadPath,
              'source_mood_raw': item.sourceMoodRaw,
              'fingerprint_sha256': item.fingerprintSha256,
            },
          )
          .toList(growable: false),
      if (localAppProfile != null)
        'local_app_profile': {
          'shift': localAppProfile!.shift,
          'parent_phone_1': localAppProfile!.parentPhone1,
          'parent_phone_2': localAppProfile!.parentPhone2,
        },
    };
  }

  String normalizeKundelikDayDateToYmd(dynamic rawDate) {
    if (rawDate == null) {
      throw ArgumentError('Kundelik day.date is null');
    }

    final raw = rawDate.toString().trim();
    if (raw.isEmpty) {
      throw ArgumentError('Kundelik day.date is empty');
    }

    final seconds = int.tryParse(raw);
    if (seconds == null) {
      throw ArgumentError('Kundelik day.date is not unix seconds: $raw');
    }

    final dt = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    );

    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  String _normalizeLessonDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return value;
    }
    final plainYmd = RegExp(r'^\d{4}-\d{2}-\d{2}$').firstMatch(value);
    if (plainYmd != null) {
      return value;
    }

    final unix = int.tryParse(value);
    if (unix != null) {
      if (value.length <= 10) {
        try {
          return normalizeKundelikDayDateToYmd(value);
        } catch (_) {}
      }
      final millis = value.length >= 13 ? unix : unix * 1000;
      final dt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    final iso = DateTime.tryParse(value);
    if (iso != null) {
      return '${iso.year.toString().padLeft(4, '0')}-${iso.month.toString().padLeft(2, '0')}-${iso.day.toString().padLeft(2, '0')}';
    }

    final dmy =
        RegExp(r'^(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4})$').firstMatch(value);
    if (dmy != null) {
      final day = dmy.group(1)!.padLeft(2, '0');
      final month = dmy.group(2)!.padLeft(2, '0');
      final year = dmy.group(3)!;
      return '$year-$month-$day';
    }
    return value;
  }

  String _normalizeLessonTime(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return '';
    }
    final hm = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(value);
    if (hm != null) {
      final hour = hm.group(1)!.padLeft(2, '0');
      final minute = hm.group(2)!.padLeft(2, '0');
      return '$hour:$minute';
    }
    final hms = RegExp(r'^(\d{1,2}):(\d{1,2}):(\d{1,2})$').firstMatch(value);
    if (hms != null) {
      final hour = hms.group(1)!.padLeft(2, '0');
      final minute = hms.group(2)!.padLeft(2, '0');
      return '$hour:$minute';
    }
    // Keep payload contract strict: avoid sending ambiguous time formats.
    return '';
  }

  int _normalizeLessonNumberForIngest(int lessonNumber) {
    return lessonNumber < 0 ? 0 : lessonNumber;
  }
}
