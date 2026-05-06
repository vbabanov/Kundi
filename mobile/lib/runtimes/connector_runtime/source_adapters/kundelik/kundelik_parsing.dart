import 'dart:convert';
import 'dart:developer' as developer;

import '../../contracts/models.dart';

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

Map<String, String> extractSourceIds(String html) {
  final personCandidates = <String>[
    ...RegExp(r'''personId["']?\s*[:=]\s*["']?(\d+)''')
        .allMatches(html)
        .map((m) => m.group(1) ?? ''),
    ...RegExp(r'''school/(\d+)/person/(\d+)''')
        .allMatches(html)
        .map((m) => m.group(2) ?? ''),
  ];
  final schoolCandidates = <String>[
    ...RegExp(r'''schoolId["']?\s*[:=]\s*["']?(\d+)''')
        .allMatches(html)
        .map((m) => m.group(1) ?? ''),
    ...RegExp(r'''school/(\d+)/person/(\d+)''')
        .allMatches(html)
        .map((m) => m.group(1) ?? ''),
  ];
  final groupCandidates = <String>[
    ...RegExp(r'''groupId["']?\s*[:=]\s*["']?(\d+)''')
        .allMatches(html)
        .map((m) => m.group(1) ?? ''),
  ];

  final person = _pickBestId(personCandidates);
  final school = _pickBestId(schoolCandidates);
  final group = _pickBestId(groupCandidates);
  return <String, String>{
    if (person.isNotEmpty) 'person_id': person,
    if (school.isNotEmpty) 'school_id': school,
    if (group.isNotEmpty) 'group_id': group,
  };
}

List<String> extractPeriodIdsFromMarksHtml(String html) {
  if (html.trim().isEmpty) {
    return const <String>[];
  }
  final out = <String>[];
  final seen = <String>{};

  void collect(RegExp pattern) {
    for (final match in pattern.allMatches(html)) {
      final raw = (match.group(1) ?? '').trim();
      if (raw.isEmpty) {
        continue;
      }
      final normalized = raw.toLowerCase();
      final isNumeric = RegExp(r'^\d+$').hasMatch(normalized);
      final isFinal = normalized == 'final';
      if (!isNumeric && !isFinal) {
        continue;
      }
      if (seen.add(normalized)) {
        out.add(normalized);
      }
    }
  }

  collect(RegExp(r'periodId=([A-Za-z0-9]+)', caseSensitive: false));
  collect(RegExp(r'"periodId"\s*:\s*"([A-Za-z0-9]+)"', caseSensitive: false));
  collect(RegExp(r'''periodId["']?\s*[:=]\s*["']?([A-Za-z0-9]+)''',
      caseSensitive: false));

  return out;
}

List<String> extractPeriodIdsFromMarksPayload(dynamic raw) {
  final parsed = raw is String ? _tryDecode(raw) : raw;
  if (parsed is! Map) {
    return const <String>[];
  }

  final out = <String>[];
  final seen = <String>{};

  void addCandidate(String rawValue) {
    final normalized = rawValue.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }
    final isNumeric = RegExp(r'^\d+$').hasMatch(normalized);
    final isFinal = normalized == 'final';
    if (!isNumeric && !isFinal) {
      return;
    }
    if (seen.add(normalized)) {
      out.add(normalized);
    }
  }

  final root = Map<String, dynamic>.from(parsed);
  addCandidate(_value(root, ['periodId']));

  final subjects = root['subjects'];
  if (subjects is! List) {
    return out;
  }
  for (final subjectRaw in subjects) {
    if (subjectRaw is! Map) {
      continue;
    }
    final subject = Map<String, dynamic>.from(subjectRaw);
    final finalWorks = subject['finalWorks'];
    if (finalWorks is! List) {
      continue;
    }
    for (final workRaw in finalWorks) {
      if (workRaw is! Map) {
        continue;
      }
      final work = Map<String, dynamic>.from(workRaw);
      addCandidate(_value(work, ['periodId']));
    }
  }

  return out;
}

String _pickBestId(Iterable<String> candidates) {
  final cleaned = candidates
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty && RegExp(r'^\d+$').hasMatch(c))
      .toList(growable: false);
  if (cleaned.isEmpty) {
    return '';
  }
  final nonZero = cleaned.where((c) => c != '0').toList(growable: false);
  if (nonZero.isEmpty) {
    return cleaned.first;
  }
  nonZero.sort((a, b) => b.length.compareTo(a.length));
  return nonZero.first;
}

SourceProfile parseProfile(String raw, {required String fallbackLogin}) {
  final firstName = _extractString(raw, 'firstName');
  final lastName = _extractString(raw, 'lastName');
  final classLabel = _extractString(raw, 'className');
  final schoolName = _extractString(raw, 'schoolName');
  final gradeLevel = _extractGradeLevel(classLabel);

  return SourceProfile(
    firstName: firstName.isEmpty ? fallbackLogin : firstName,
    lastName: lastName,
    gradeLevel: gradeLevel,
    classLabel: classLabel,
    schoolName: schoolName,
    classTeacherFullName: '',
  );
}

List<SourceLesson> parseLessons(dynamic rawBody) {
  final dynamic parsed = rawBody is String ? _tryDecode(rawBody) : rawBody;
  final List<dynamic> entries = _extractLessonEntries(parsed);
  final lessons = <SourceLesson>[];

  for (final entry in entries) {
    if (entry is! Map) {
      continue;
    }
    final map = Map<String, dynamic>.from(entry);
    final sourceLessonKey =
        _value(map, ['id', 'lessonId', 'sourceLessonKey', 'logEntryId']);
    final date =
        _normalizeDate(_value(map, ['date', 'lessonDate', 'dateText']));
    final subject = _extractSubject(map);
    if (date.isEmpty || subject.isEmpty) {
      continue;
    }

    final grades = _extractGrades(map, sourceLessonKey, date);

    lessons.add(
      SourceLesson(
        sourceLessonKey: sourceLessonKey.isEmpty
            ? '$date:${_value(map, ['lessonNumber', 'number'])}:$subject'
            : sourceLessonKey,
        date: date,
        lessonNumber: _toLessonNumber(
          _value(
            map,
            [
              'lessonNumber',
              'number',
              'lesson_number',
              'lessonNo',
              'lesson_num',
              'numInDay',
              'order',
            ],
          ),
        ),
        subjectName: subject,
        lessonPlace: _value(
            map, ['place', 'lessonPlace', 'classroom', 'room', 'cabinet']),
        startTime: _resolveLessonStartTime(map),
        endTime: _resolveLessonEndTime(map),
        topicTitle: _value(map, ['topicTitle', 'topic', 'theme']),
        homeworkText: _extractHomeworkText(map),
        requiresPhoto: _toBool(map['requiresPhoto']) ||
            _toBool((map['homework'] is Map
                ? (map['homework'] as Map)['requiresPhoto']
                : null)),
        grades: grades,
      ),
    );
  }
  return lessons;
}

dynamic _tryDecode(String source) {
  try {
    return jsonDecode(source);
  } catch (_) {
    return source;
  }
}

List<dynamic> _extractLessonEntries(dynamic root) {
  if (root is List) {
    return root;
  }
  if (root is Map) {
    final map = Map<String, dynamic>.from(root);
    final candidates = [
      map['lessons'],
      map['days'],
      map['items'],
      map['result'],
      map['data']
    ];
    for (final candidate in candidates) {
      if (candidate is List) {
        if (candidate.isNotEmpty &&
            candidate.first is Map &&
            (candidate.first as Map).containsKey('lessons')) {
          final nested = <dynamic>[];
          for (final day in candidate) {
            if (day is Map && day['lessons'] is List) {
              final dayMap = Map<String, dynamic>.from(day);
              final dayDateRaw =
                  _value(dayMap, ['date', 'dayDate', 'dateText']);
              String dayDateNormalized;
              final daySeconds = int.tryParse(dayDateRaw);
              if (daySeconds != null && dayDateRaw.length <= 10) {
                try {
                  dayDateNormalized = normalizeKundelikDayDateToYmd(dayDateRaw);
                } catch (_) {
                  dayDateNormalized = _normalizeDate(dayDateRaw);
                }
              } else {
                dayDateNormalized = _normalizeDate(dayDateRaw);
              }
              final dayLessons = day['lessons'] as List;
              for (final lesson in dayLessons) {
                if (lesson is! Map) {
                  continue;
                }
                final lessonMap = Map<String, dynamic>.from(lesson);
                lessonMap.putIfAbsent('date', () => dayDateNormalized);
                if (dayMap['groupId'] != null && lessonMap['groupId'] == null) {
                  lessonMap['groupId'] = dayMap['groupId'];
                }
                nested.add(lessonMap);
              }
            }
          }
          return nested;
        }
        return candidate;
      }
    }
  }
  return const <dynamic>[];
}

String _extractString(String source, String key) {
  final direct =
      RegExp('"$key"\\s*:\\s*"([^"]+)"').firstMatch(source)?.group(1) ?? '';
  if (direct.isNotEmpty) {
    return direct.trim();
  }
  return '';
}

String _value(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    if (!map.containsKey(key)) {
      continue;
    }
    final value = map[key];
    if (value == null) {
      continue;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

int _extractGradeLevel(String classLabel) {
  final match = RegExp(r'(\d{1,2})').firstMatch(classLabel);
  if (match == null) {
    return 1;
  }
  final parsed = int.tryParse(match.group(1) ?? '');
  if (parsed == null || parsed <= 0) {
    return 1;
  }
  return parsed > 12 ? 12 : parsed;
}

int _toInt(String value, {required int fallback}) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

int _toLessonNumber(String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null) {
    return 0;
  }
  return parsed < 0 ? 0 : parsed;
}

bool _toBool(Object? raw) {
  if (raw is bool) {
    return raw;
  }
  final text = (raw ?? '').toString().toLowerCase();
  return text == '1' || text == 'true';
}

String _normalizeGradeType(String raw) {
  switch (raw.toLowerCase()) {
    case 'absence':
    case 'behavior':
      return raw.toLowerCase();
    default:
      return 'regular';
  }
}

String _extractSubject(Map<String, dynamic> map) {
  final direct = _value(map, ['subjectName', 'subject', 'discipline']);
  if (direct.isNotEmpty && !direct.startsWith('{')) {
    return direct;
  }
  final subject = map['subject'];
  if (subject is Map) {
    final subjectMap = Map<String, dynamic>.from(subject);
    final fromMap = _value(subjectMap, ['name', 'title', 'subjectName']);
    if (fromMap.isNotEmpty) {
      return fromMap;
    }
  }
  return direct;
}

String _extractHomeworkText(Map<String, dynamic> map) {
  final direct = _value(map, ['homeworkText', 'homework', 'task']);
  if (direct.isNotEmpty && !direct.startsWith('{')) {
    return direct;
  }
  final homework = map['homework'];
  if (homework is Map) {
    final homeworkMap = Map<String, dynamic>.from(homework);
    final text = _value(homeworkMap, ['text', 'description', 'task']);
    if (text.isNotEmpty) {
      return text;
    }
  }
  return direct;
}

List<SourceGrade> _extractGrades(
  Map<String, dynamic> map,
  String sourceLessonKey,
  String date,
) {
  final out = <SourceGrade>[];
  final gradesSource = (map['grades'] is List)
      ? map['grades']
      : (map['workMarks'] is List ? map['workMarks'] : const <dynamic>[]);
  if (gradesSource is! List) {
    return out;
  }

  for (var index = 0; index < gradesSource.length; index++) {
    final grade = gradesSource[index];
    if (grade is! Map) {
      continue;
    }
    final gradeMap = Map<String, dynamic>.from(grade);
    final value = _value(gradeMap, ['value', 'text', 'gradeText', 'mark']);
    if (value.isEmpty) {
      continue;
    }
    out.add(
      SourceGrade(
        sourceGradeKey: _value(gradeMap, ['id', 'gradeId', 'workId']).isEmpty
            ? '${sourceLessonKey.isEmpty ? date : sourceLessonKey}:$index'
            : _value(gradeMap, ['id', 'gradeId', 'workId']),
        value: value,
        mood: _value(gradeMap, ['mood', 'comment']),
        type: _normalizeGradeType(_value(gradeMap, ['type', 'gradeType'])),
        isAbsent:
            value.toLowerCase() == 'РЅ' || value.toLowerCase() == 'absent',
      ),
    );
  }
  return out;
}

String _normalizeDate(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return '';
  }

  final plainYmd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
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

  final ymd =
      RegExp(r'^(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})$').firstMatch(value);
  if (ymd != null) {
    final year = ymd.group(1)!;
    final month = ymd.group(2)!.padLeft(2, '0');
    final day = ymd.group(3)!.padLeft(2, '0');
    return '$year-$month-$day';
  }
  return value;
}

String _normalizeHm(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return '';
  }

  final match = RegExp(r'^(\d{1,2}):(\d{1,2})(?::\d{1,2})?$').firstMatch(value);
  if (match != null) {
    final hour = match.group(1)!.padLeft(2, '0');
    final minute = match.group(2)!.padLeft(2, '0');
    return '$hour:$minute';
  }
  return value;
}

String _resolveLessonStartTime(Map<String, dynamic> map) {
  final fromHours = _extractHoursHm(map, isStart: true);
  if (fromHours.isNotEmpty) {
    return fromHours;
  }
  return _normalizeHm(
    _value(
      map,
      [
        'startTime',
        'beginTime',
        'start_time',
        'begin_time',
        'lessonStartTime',
        'lesson_start_time',
        'start',
        'timeStart',
        'time_start',
        'from',
      ],
    ),
  );
}

String _resolveLessonEndTime(Map<String, dynamic> map) {
  final fromHours = _extractHoursHm(map, isStart: false);
  if (fromHours.isNotEmpty) {
    return fromHours;
  }
  return _normalizeHm(
    _value(
      map,
      [
        'endTime',
        'finishTime',
        'end_time',
        'finish_time',
        'lessonEndTime',
        'lesson_end_time',
        'end',
        'timeEnd',
        'time_end',
        'to',
      ],
    ),
  );
}

String _extractHoursHm(
  Map<String, dynamic> map, {
  required bool isStart,
}) {
  final hoursRaw = map['hours'];
  if (hoursRaw is! Map) {
    return '';
  }
  final hours = Map<String, dynamic>.from(hoursRaw);
  final hourRaw = _value(hours, [
    isStart ? 'startHour' : 'endHour',
  ]);
  final minuteRaw = _value(hours, [
    isStart ? 'startMinute' : 'endMinute',
  ]);
  final hour = int.tryParse(hourRaw);
  final minute = int.tryParse(minuteRaw);
  if (hour == null || minute == null) {
    return '';
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return '';
  }
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class KundelikChatIdentity {
  const KundelikChatIdentity({
    required this.schoolName,
    required this.classLabel,
    required this.classTeacherJid,
    required this.studentJid,
  });

  final String schoolName;
  final String classLabel;
  final String classTeacherJid;
  final String studentJid;
}

class KundelikAcademicPayload {
  const KundelikAcademicPayload({
    required this.results,
    required this.aggregates,
    required this.attendance,
  });

  final List<SourceAcademicResult> results;
  final List<SourceAcademicAggregate> aggregates;
  final List<SourceAttendanceEvent> attendance;

  KundelikAcademicPayload merge(KundelikAcademicPayload other) {
    final mergedResults = <SourceAcademicResult>[
      ...results,
      ...other.results,
    ];
    final mergedAggregates = <SourceAcademicAggregate>[
      ...aggregates,
      ...other.aggregates,
    ];
    final mergedAttendance = <SourceAttendanceEvent>[
      ...attendance,
      ...other.attendance,
    ];
    return KundelikAcademicPayload(
      results: mergedResults,
      aggregates: mergedAggregates,
      attendance: mergedAttendance,
    );
  }
}

KundelikChatIdentity parseChatIdentity({
  required dynamic closeContactsRaw,
  required String targetGroupId,
  required String targetPersonId,
}) {
  final parsed = closeContactsRaw is String
      ? _tryDecode(closeContactsRaw)
      : closeContactsRaw;
  if (parsed is! Map) {
    return const KundelikChatIdentity(
      schoolName: '',
      classLabel: '',
      classTeacherJid: '',
      studentJid: '',
    );
  }
  final root = Map<String, dynamic>.from(parsed);
  final contacts = root['contacts'];
  if (contacts is! List) {
    return const KundelikChatIdentity(
      schoolName: '',
      classLabel: '',
      classTeacherJid: '',
      studentJid: '',
    );
  }

  String schoolName = '';
  String classLabel = '';
  String classTeacherJid = '';
  String studentJid = '';
  String fallbackSchoolName = '';
  String fallbackTeacherJid = '';

  for (final item in contacts) {
    if (item is! Map) {
      continue;
    }
    final map = Map<String, dynamic>.from(item);
    final candidateSchoolName = _value(map, ['schoolName', 'name', 'school']);
    final candidateTeacherJid =
        _value(map, ['classTeacher', 'classTeacherJid']);
    if (fallbackSchoolName.isEmpty && candidateSchoolName.isNotEmpty) {
      fallbackSchoolName = candidateSchoolName;
    }
    if (fallbackTeacherJid.isEmpty && candidateTeacherJid.isNotEmpty) {
      fallbackTeacherJid = candidateTeacherJid;
    }

    final groups = map['groups'];
    final candidateLabel =
        _extractGroupName(groups, targetGroupId: targetGroupId);
    final candidateJid = _extractStudentJid(
      map: map,
      targetPersonId: targetPersonId,
    );
    final isMatchedContact =
        candidateLabel.isNotEmpty || candidateJid.isNotEmpty;
    if (isMatchedContact) {
      if (candidateLabel.isNotEmpty) {
        classLabel = candidateLabel;
      }
      if (candidateJid.isNotEmpty) {
        studentJid = candidateJid;
      }
      if (candidateSchoolName.isNotEmpty) {
        schoolName = candidateSchoolName;
      }
      if (candidateTeacherJid.isNotEmpty) {
        classTeacherJid = candidateTeacherJid;
      }
    }
  }

  if (schoolName.isEmpty) {
    schoolName = fallbackSchoolName;
  }
  if (classTeacherJid.isEmpty) {
    classTeacherJid = fallbackTeacherJid;
  }

  return KundelikChatIdentity(
    schoolName: schoolName,
    classLabel: classLabel,
    classTeacherJid: classTeacherJid,
    studentJid: studentJid,
  );
}

Map<String, String> parseEnrichNames(dynamic enrichRaw) {
  final parsed = enrichRaw is String ? _tryDecode(enrichRaw) : enrichRaw;
  final out = <String, String>{};
  final jidPattern =
      RegExp(r'^user_\d+@xmpp\.kundelik\.kz$', caseSensitive: false);

  void walk(dynamic node) {
    if (node is List) {
      for (final item in node) {
        walk(item);
      }
      return;
    }
    if (node is! Map) {
      return;
    }
    final map = Map<String, dynamic>.from(node);
    for (final entry in map.entries) {
      final key = entry.key.trim();
      final value = entry.value;
      if (jidPattern.hasMatch(key)) {
        if (value is String && value.trim().isNotEmpty) {
          out[key] = value.trim();
        } else if (value is Map) {
          final nestedMap = Map<String, dynamic>.from(value);
          final nestedName =
              _value(nestedMap, ['name', 'shortName', 'displayName']);
          if (nestedName.isNotEmpty) {
            out[key] = nestedName;
          }
        }
      }
    }

    final jid = _value(map, ['jid', 'id', 'peerJid']);
    final name = _value(map, ['name', 'shortName', 'displayName']);
    if (jid.isNotEmpty && name.isNotEmpty) {
      out[jid] = name;
    }
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is Map || value is List) {
        walk(value);
      }
    }
  }

  walk(parsed);
  return out;
}

KundelikAcademicPayload parsePeriodAcademicPayload(
  dynamic raw, {
  required String sourceEndpoint,
}) {
  final parsed = raw is String ? _tryDecode(raw) : raw;
  if (parsed is! Map) {
    return const KundelikAcademicPayload(
      results: <SourceAcademicResult>[],
      aggregates: <SourceAcademicAggregate>[],
      attendance: <SourceAttendanceEvent>[],
    );
  }
  final root = Map<String, dynamic>.from(parsed);
  final periodId = _value(root, ['periodId']);
  final dateFinish = _normalizeDate(_value(root, ['dateFinish']));
  final subjects = root['subjects'];
  if (subjects is! List) {
    return const KundelikAcademicPayload(
      results: <SourceAcademicResult>[],
      aggregates: <SourceAcademicAggregate>[],
      attendance: <SourceAttendanceEvent>[],
    );
  }

  final results = <SourceAcademicResult>[];
  final aggregates = <SourceAcademicAggregate>[];
  final attendance = <SourceAttendanceEvent>[];
  var subjectCount = 0;
  var worksCount = 0;
  var workMarksCount = 0;
  var summativeMarksCount = 0;
  var finalWorksCount = 0;

  for (final subjectRaw in subjects) {
    if (subjectRaw is! Map) {
      continue;
    }
    subjectCount++;
    final subject = Map<String, dynamic>.from(subjectRaw);
    final subjectId = _value(subject, ['id']);
    final subjectName = _value(subject, ['name']);
    final works = subject['works'];
    if (works is List) {
      worksCount += works.length;
      for (final workRaw in works) {
        if (workRaw is! Map) {
          continue;
        }
        final work = Map<String, dynamic>.from(workRaw);
        final workId = _value(work, ['workId', 'id']);
        final recordedOn = _normalizeDate(_value(work, ['date']));
        final lessonNumber =
            _toInt(_value(work, ['lessonNumber']), fallback: 0);
        final lessonRefKey = _value(work, ['lessonId']).isNotEmpty
            ? _value(work, ['lessonId'])
            : '$subjectId:$recordedOn:$lessonNumber';
        final workName = _value(work, ['name']);
        final summativeFromWork =
            _isTruePath(work, ['type', 'isSummativeWork']);
        final marks = work['marks'];
        if (marks is! List) {
          continue;
        }
        workMarksCount += marks.length;
        for (var i = 0; i < marks.length; i++) {
          final markRaw = marks[i];
          if (markRaw is! Map) {
            continue;
          }
          final mark = Map<String, dynamic>.from(markRaw);
          final valueText = _value(mark, ['value', 'text', 'mark']);
          if (valueText.isEmpty || recordedOn.isEmpty) {
            continue;
          }
          final markId = _value(mark, ['id', 'markId']);
          final mood = _normalizeMood(_value(mark, ['mood']));
          final resultKind = summativeFromWork
              ? _mapSummativeKind(workName, fallback: 'sor')
              : 'regular';
          final termNo = _termNoFromPeriodId(periodId);
          results.add(
            SourceAcademicResult(
              sourceResultKey:
                  markId.isEmpty ? '$workId:$recordedOn:$i:$valueText' : markId,
              resultKind: resultKind,
              providerWorkId: workId,
              providerMarkId: markId,
              providerSubjectId: subjectId,
              subjectName: subjectName,
              lessonRefKey: lessonRefKey,
              recordedOn: recordedOn,
              periodId: periodId,
              termNo: termNo,
              valueText: valueText,
              valueNumeric: double.tryParse(valueText),
              resolvedMood: mood,
              sourceEndpoint: sourceEndpoint,
              sourceMoodRaw: _value(mark, ['mood']),
            ),
          );
        }
      }
    }

    final summativeMarks = subject['summativeMarks'];
    if (summativeMarks is List) {
      summativeMarksCount += summativeMarks.length;
      for (var i = 0; i < summativeMarks.length; i++) {
        final summativeRaw = summativeMarks[i];
        if (summativeRaw is! Map) {
          continue;
        }
        final summative = Map<String, dynamic>.from(summativeRaw);
        final rawType = _value(summative, ['type']);
        final kind = _mapSummativeKind(rawType, fallback: '');
        if (kind.isEmpty) {
          continue;
        }
        final value = _value(summative, ['value']);
        final maxValue = _value(summative, ['maxValue']);
        final valueText = value.isEmpty
            ? ''
            : maxValue.isEmpty
                ? value
                : '$value/$maxValue';
        if (valueText.isEmpty) {
          continue;
        }
        final markId = _value(summative, ['markId', 'id']);
        final sectionId = _value(summative, ['sectionId', 'workId']);
        final termNo = _termNoFromPeriodId(periodId);
        final recordedOn = dateFinish.isEmpty ? _todayYmd() : dateFinish;
        results.add(
          SourceAcademicResult(
            sourceResultKey:
                markId.isEmpty ? '$sectionId:$recordedOn:$kind:$i' : markId,
            resultKind: kind,
            providerWorkId: sectionId,
            providerMarkId: markId,
            providerSubjectId: subjectId,
            subjectName: subjectName,
            lessonRefKey: '',
            recordedOn: recordedOn,
            periodId: periodId,
            termNo: termNo,
            valueText: valueText,
            valueNumeric: double.tryParse(value),
            resolvedMood: _normalizeMood(_value(summative, ['mood'])),
            sourceEndpoint: sourceEndpoint,
            sourceMoodRaw: _value(summative, ['mood']),
          ),
        );
      }
    }

    final finalWorks = subject['finalWorks'];
    if (finalWorks is List) {
      finalWorksCount += finalWorks.length;
      for (var workIdx = 0; workIdx < finalWorks.length; workIdx++) {
        final aggregateWorkRaw = finalWorks[workIdx];
        if (aggregateWorkRaw is! Map) {
          continue;
        }
        final aggregateWork = Map<String, dynamic>.from(aggregateWorkRaw);
        final workId = _value(aggregateWork, ['workId', 'id']);
        final workPeriodId = _value(aggregateWork, ['periodId']);
        final periodNumberRaw =
            int.tryParse(_value(aggregateWork, ['periodNumber']));
        final kind = _mapAggregateKind(
          rawType: _value(aggregateWork, ['type']),
          periodNumber: periodNumberRaw,
          periodId: workPeriodId,
        );
        if (kind.isEmpty) {
          continue;
        }
        final marks = aggregateWork['marks'];
        if (marks is! List) {
          continue;
        }
        for (var markIdx = 0; markIdx < marks.length; markIdx++) {
          final markRaw = marks[markIdx];
          if (markRaw is! Map) {
            continue;
          }
          final mark = Map<String, dynamic>.from(markRaw);
          final valueText = _value(mark, ['value', 'text', 'mark']);
          if (valueText.isEmpty) {
            continue;
          }
          final markId = _value(mark, ['id', 'markId']);
          final recordedOn = dateFinish.isEmpty ? _todayYmd() : dateFinish;
          final termNo = kind == 'term'
              ? _normalizeTermNo(
                  periodNumberRaw: periodNumberRaw,
                  periodId: workPeriodId.isEmpty ? periodId : workPeriodId,
                )
              : null;
          final yearLabel = kind == 'year'
              ? _yearLabelFromPeriodId(
                  workPeriodId.isEmpty ? periodId : workPeriodId)
              : '';
          if (kind == 'year' && yearLabel.isEmpty) {
            continue;
          }
          aggregates.add(
            SourceAcademicAggregate(
              sourceAggregateKey: markId.isEmpty
                  ? '$workId:$recordedOn:$kind:$markIdx'
                  : '$workId:$markId',
              resultKind: kind,
              providerSubjectId: subjectId,
              subjectName: subjectName,
              recordedOn: recordedOn,
              periodId: workPeriodId.isEmpty ? periodId : workPeriodId,
              termNo: termNo,
              yearLabel: yearLabel,
              valueText: valueText,
              valueNumeric: double.tryParse(valueText),
              resolvedMood: _normalizeMood(_value(mark, ['mood'])),
              sourceEndpoint: sourceEndpoint,
              sourceMoodRaw: _value(mark, ['mood']),
            ),
          );
        }
      }
    }

    final logs = subject['lessonLogEntries'];
    if (logs is List) {
      for (var idx = 0; idx < logs.length; idx++) {
        final logRaw = logs[idx];
        if (logRaw is! Map) {
          continue;
        }
        final log = Map<String, dynamic>.from(logRaw);
        final rawCode = _value(log, ['value', 'lessonLogEntryValue']);
        final reason = _value(log, ['fullName', 'text']);
        final normalizedStatus = normalizeKundelikAttendanceCode(
          rawValue: rawCode,
          fullName: reason,
        );
        final recordedOn =
            _normalizeDate(_value(log, ['date', 'recordedOn', 'eventDate']));
        if (recordedOn.isEmpty || normalizedStatus == null) {
          if ((rawCode.trim().isNotEmpty || reason.trim().isNotEmpty) &&
              recordedOn.isNotEmpty) {
            developer.log(
              jsonEncode(<String, dynamic>{
                'stage': 'kundelik_attendance_skip_unknown',
                'raw_code': rawCode,
                'full_name': reason,
                'recorded_on': recordedOn,
              }),
              name: 'KUNDI_LIVE',
            );
          }
          continue;
        }
        final eventId = _value(log, ['id']);
        final lessonRef = _value(log, ['lessonId']);
        final lessonNumber = _toInt(
          _value(
            log,
            [
              'lessonNumber',
              'number',
              'lesson_number',
              'lessonNo',
              'lesson_num',
              'numInDay',
              'order',
            ],
          ),
          fallback: 0,
        );
        attendance.add(
          SourceAttendanceEvent(
            sourceEventKey:
                eventId.isEmpty ? '$lessonRef:$recordedOn:$idx' : eventId,
            providerEventKey: eventId,
            providerLessonRef: lessonRef,
            providerSubjectId: subjectId,
            subjectName: subjectName,
            lessonNumber: lessonNumber,
            date: recordedOn,
            code: normalizedStatus,
            reason: reason,
            normalizedStatus: normalizedStatus,
          ),
        );
      }
    }
  }

  developer.log(
    jsonEncode(<String, dynamic>{
      'stage': 'kundelik_parsing_period_counts',
      'source_endpoint': sourceEndpoint,
      'subject_count': subjectCount,
      'works_count': worksCount,
      'work_marks_count': workMarksCount,
      'summative_marks_count': summativeMarksCount,
      'final_works_count': finalWorksCount,
      'mapped_results_count': results.length,
      'mapped_aggregates_count': aggregates.length,
      'mapped_attendance_count': attendance.length,
    }),
    name: 'KUNDI_LIVE',
  );

  return KundelikAcademicPayload(
    results: results,
    aggregates: aggregates,
    attendance: attendance,
  );
}

String _extractGroupName(
  dynamic groups, {
  required String targetGroupId,
}) {
  if (groups is List) {
    for (final entry in groups) {
      if (entry is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(entry);
      final id = _value(map, ['id', 'groupId']);
      final name = _value(map, ['name', 'title']);
      if (name.isEmpty) {
        continue;
      }
      if (targetGroupId.isEmpty || id == targetGroupId) {
        return name;
      }
    }
    return '';
  }
  if (groups is Map) {
    final map = Map<String, dynamic>.from(groups);
    if (targetGroupId.isNotEmpty && map.containsKey(targetGroupId)) {
      final hit = map[targetGroupId];
      if (hit is Map) {
        final hitMap = Map<String, dynamic>.from(hit);
        final name = _value(hitMap, ['name', 'title']);
        if (name.isNotEmpty) {
          return name;
        }
      } else if (hit is String) {
        return hit.trim();
      }
    }
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is Map) {
        final hitMap = Map<String, dynamic>.from(value);
        final name = _value(hitMap, ['name', 'title']);
        final id = _value(hitMap, ['id', 'groupId']);
        if (name.isEmpty) {
          continue;
        }
        if (targetGroupId.isEmpty ||
            id == targetGroupId ||
            entry.key == targetGroupId) {
          return name;
        }
      } else if (value is String && entry.key == targetGroupId) {
        return value.trim();
      }
    }
  }
  return '';
}

String _extractStudentJid({
  required Map<String, dynamic> map,
  required String targetPersonId,
}) {
  final direct = _value(map, ['jid', 'peerJid']);
  final directPerson = _value(map, ['personId', 'person_id']);
  if (direct.isNotEmpty &&
      RegExp(r'^user_\d+@xmpp\.kundelik\.kz$', caseSensitive: false)
          .hasMatch(direct) &&
      (targetPersonId.isEmpty || directPerson == targetPersonId)) {
    return direct;
  }

  final members = map['members'];
  if (members is List) {
    for (final memberRaw in members) {
      if (memberRaw is! Map) {
        continue;
      }
      final member = Map<String, dynamic>.from(memberRaw);
      final personId = _value(member, ['personId', 'person_id', 'id']);
      final jid = _value(member, ['jid', 'peerJid']);
      if (jid.isEmpty) {
        continue;
      }
      if (targetPersonId.isEmpty || personId == targetPersonId) {
        return jid;
      }
    }
  }
  return '';
}

bool _isTruePath(Map<String, dynamic> map, List<String> path) {
  dynamic cursor = map;
  for (final key in path) {
    if (cursor is! Map || !cursor.containsKey(key)) {
      return false;
    }
    cursor = cursor[key];
  }
  if (cursor is bool) {
    return cursor;
  }
  final text = (cursor ?? '').toString().toLowerCase().trim();
  return text == 'true' || text == '1';
}

String _mapSummativeKind(String raw, {required String fallback}) {
  final token = raw.toLowerCase().trim();
  if (token.isEmpty) {
    return fallback;
  }
  if (_containsAny(token, ['soch', 'соч', 'СЃРѕС‡', 'СЂСћСЂС›СЂВ§'])) {
    return 'soch';
  }
  if (_containsAny(token, ['sor', 'сор', 'СЃРѕСЂ', 'СЂСћСЂС›СЂВ '])) {
    return 'sor';
  }
  return fallback;
}

String _mapAggregateKind({
  required String rawType,
  required int? periodNumber,
  required String periodId,
}) {
  final token = rawType.toLowerCase().trim();
  if (_containsAny(token, ['year', 'РіРѕРґ', 'СЂвЂњСЂС•СЂТ‘'])) {
    return 'year';
  }
  if (_containsAny(
      token, ['period', 'quarter', 'term', 'С‡РµС‚РІ', 'СЂВ§СЂВµСЃвЂљ'])) {
    return 'term';
  }
  if (periodNumber != null) {
    return 'term';
  }
  if (periodId.toLowerCase() == 'final') {
    return 'year';
  }
  return '';
}

bool _containsAny(String value, List<String> tokens) {
  for (final token in tokens) {
    if (value.contains(token)) {
      return true;
    }
  }
  return false;
}

int? _termNoFromPeriodId(String periodId) {
  final value = periodId.trim();
  if (value.isEmpty || value.toLowerCase() == 'final') {
    return null;
  }
  final last = value.isEmpty ? '' : value.substring(value.length - 1);
  final parsed = int.tryParse(last);
  if (parsed == null || parsed <= 0) {
    return null;
  }
  return parsed;
}

int? _normalizeTermNo({
  required int? periodNumberRaw,
  required String periodId,
}) {
  if (periodNumberRaw != null) {
    final adjusted = periodNumberRaw + 1;
    if (adjusted > 0) {
      return adjusted;
    }
  }
  return _termNoFromPeriodId(periodId) ?? 1;
}

String _yearLabelFromPeriodId(String periodId) {
  final value = periodId.trim();
  if (value.isEmpty || value.toLowerCase() == 'final') {
    final now = DateTime.now().toUtc();
    return '${now.year}/${now.year + 1}';
  }
  return '';
}

String _normalizeMood(String rawMood) {
  final normalized = rawMood.trim().toLowerCase();
  if (normalized.isEmpty) {
    return 'unknown';
  }
  return normalized;
}

String? normalizeKundelikAttendanceCode({
  required String rawValue,
  required String fullName,
}) {
  final rawToken = _normalizeAttendanceToken(rawValue);
  final reasonToken = _normalizeAttendanceToken(fullName);

  if (rawToken.isEmpty && reasonToken.isEmpty) {
    return null;
  }

  if (_isCanonicalAttendance(rawToken)) {
    return rawToken;
  }
  if (_isCanonicalAttendance(reasonToken)) {
    return reasonToken;
  }

  if (rawToken == 'н' ||
      reasonToken.contains('неявк') ||
      reasonToken.contains('безуваж')) {
    return 'absent';
  }

  if (rawToken == 'б' ||
      rawToken == 'п' ||
      reasonToken.contains('боле') ||
      reasonToken.contains('поболез') ||
      reasonToken.contains('уваж')) {
    return 'excused';
  }

  if (rawToken == 'о' || reasonToken.contains('опозд')) {
    return 'late';
  }

  if (rawToken == '+' ||
      reasonToken.contains('присутств') ||
      reasonToken.contains('науроке')) {
    return 'present';
  }

  return null;
}

String _normalizeAttendanceToken(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9\+]'), '');
}

bool _isCanonicalAttendance(String value) {
  switch (value) {
    case 'present':
    case 'absent':
    case 'late':
    case 'excused':
      return true;
    default:
      return false;
  }
}

String _todayYmd() {
  final now = DateTime.now().toUtc();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

Map<String, String> extractDiaryDayDateSamples(dynamic rawBody) {
  final dynamic parsed = rawBody is String ? _tryDecode(rawBody) : rawBody;
  if (parsed is! Map) {
    return const <String, String>{
      'raw_day_date_sample': '',
      'normalized_day_date_sample': '',
    };
  }
  final map = Map<String, dynamic>.from(parsed);
  final days = map['days'];
  if (days is! List || days.isEmpty || days.first is! Map) {
    return const <String, String>{
      'raw_day_date_sample': '',
      'normalized_day_date_sample': '',
    };
  }
  final firstDay = Map<String, dynamic>.from(days.first as Map);
  final raw = _value(firstDay, ['date', 'dayDate', 'dateText']);
  String normalized = '';
  final seconds = int.tryParse(raw);
  if (seconds != null && raw.length <= 10) {
    try {
      normalized = normalizeKundelikDayDateToYmd(raw);
    } catch (_) {
      normalized = _normalizeDate(raw);
    }
  } else {
    normalized = _normalizeDate(raw);
  }
  return <String, String>{
    'raw_day_date_sample': raw,
    'normalized_day_date_sample': normalized,
  };
}
