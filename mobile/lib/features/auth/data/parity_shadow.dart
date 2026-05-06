class ParityShadowOutcome {
  const ParityShadowOutcome({
    required this.countMatch,
    required this.identityMatch,
    required this.moodMatch,
    required this.aggregateMatch,
    required this.attendanceStatusMatch,
    required this.profileMismatch,
    required this.mismatchReason,
    required this.v1ResultsCount,
    required this.v2ResultsCount,
    required this.v1LessonsCount,
    required this.v2LessonsCount,
    required this.v1AttendanceCount,
    required this.v2AttendanceCount,
    required this.v1AggregatesCount,
    required this.v2AggregatesCount,
  });

  final bool countMatch;
  final bool identityMatch;
  final bool moodMatch;
  final bool aggregateMatch;
  final bool attendanceStatusMatch;
  final bool profileMismatch;
  final String mismatchReason;
  final int v1ResultsCount;
  final int v2ResultsCount;
  final int v1LessonsCount;
  final int v2LessonsCount;
  final int v1AttendanceCount;
  final int v2AttendanceCount;
  final int v1AggregatesCount;
  final int v2AggregatesCount;
}

class _RegularV2Ref {
  const _RegularV2Ref({
    required this.providerWorkId,
    required this.providerMarkId,
  });

  final String providerWorkId;
  final String providerMarkId;
}

ParityShadowOutcome evaluateTypedReadParityShadow({
  required Map<String, dynamic> v1Profile,
  required List<dynamic> v1Grades,
  required List<dynamic> v1Lessons,
  required List<dynamic> v1Attendance,
  required Map<String, dynamic> v2Identity,
  required List<dynamic> v2Results,
  required List<dynamic> v2Lessons,
  required List<dynamic> v2Aggregates,
  required List<dynamic> v2Attendance,
  required String windowFrom,
  required String windowTo,
}) {
  final v1LessonsInWindow = _filterRowsByDate(v1Lessons, windowFrom, windowTo);
  final v1AttendanceInWindow =
      _filterRowsByDate(v1Attendance, windowFrom, windowTo);

  final v1RegularCounts = _buildV1RegularCounts(v1LessonsInWindow);
  final v2RegularCounts = _buildV2RegularCounts(v2Results);
  final regularCountsMatch = _intMapEquals(v1RegularCounts, v2RegularCounts);
  final regularIdentityAmbiguous =
      _hasAmbiguousRegularIdentity(v1RegularCounts, v2Results);

  final v1SummativeCounts =
      _buildV1SummativeCounts(v1Grades, windowFrom, windowTo);
  final v2SummativeCounts = _buildV2SummativeCounts(v2Results);
  final summativeIdentityMatch =
      _intMapEquals(v1SummativeCounts, v2SummativeCounts);
  final resultIdentityMatch =
      regularCountsMatch && summativeIdentityMatch && !regularIdentityAmbiguous;

  final v1AggregateCounts =
      _buildV1AggregateCounts(v1Grades, windowFrom, windowTo);
  final v2AggregateCounts = _buildV2AggregateCounts(v2Aggregates);
  final aggregateMatch = _intMapEquals(v1AggregateCounts, v2AggregateCounts);

  final v1AttendanceStatuses =
      _buildV1AttendanceStatusMap(v1AttendanceInWindow);
  final v2AttendanceStatuses = _buildV2AttendanceStatusMap(v2Attendance);
  final attendanceStatusMatch =
      _intMapEquals(v1AttendanceStatuses, v2AttendanceStatuses);

  final profileMismatch = _profileFieldMismatch(
        _string(v1Profile['class_label']),
        _string(v2Identity['class_label']),
      ) ||
      _profileFieldMismatch(
        _string(v1Profile['school_name']),
        _string(v2Identity['school_name']),
      );

  final identityMatch =
      resultIdentityMatch && attendanceStatusMatch && !profileMismatch;

  final moodMatch = identityMatch
      ? _compareMoodMaps(
          v1Lessons: v1LessonsInWindow,
          v1Grades: v1Grades,
          v2Results: v2Results,
          windowFrom: windowFrom,
          windowTo: windowTo,
        )
      : true;

  final countMatch = v1RegularCounts.values.fold<int>(0, (sum, x) => sum + x) +
              v1SummativeCounts.values.fold<int>(0, (sum, x) => sum + x) ==
          v2RegularCounts.values.fold<int>(0, (sum, x) => sum + x) +
              v2SummativeCounts.values.fold<int>(0, (sum, x) => sum + x) &&
      v1LessonsInWindow.length == v2Lessons.length &&
      v1AttendanceInWindow.length == v2Attendance.length;

  return ParityShadowOutcome(
    countMatch: countMatch,
    identityMatch: identityMatch,
    moodMatch: moodMatch,
    aggregateMatch: aggregateMatch,
    attendanceStatusMatch: attendanceStatusMatch,
    profileMismatch: profileMismatch,
    mismatchReason: parityMismatchReason(
      countMatch: countMatch,
      identityMatch: identityMatch,
      moodMatch: moodMatch,
      aggregateMatch: aggregateMatch,
    ),
    v1ResultsCount: v1RegularCounts.values.fold<int>(0, (sum, x) => sum + x) +
        v1SummativeCounts.values.fold<int>(0, (sum, x) => sum + x),
    v2ResultsCount: v2RegularCounts.values.fold<int>(0, (sum, x) => sum + x) +
        v2SummativeCounts.values.fold<int>(0, (sum, x) => sum + x),
    v1LessonsCount: v1LessonsInWindow.length,
    v2LessonsCount: v2Lessons.length,
    v1AttendanceCount: v1AttendanceInWindow.length,
    v2AttendanceCount: v2Attendance.length,
    v1AggregatesCount:
        v1AggregateCounts.values.fold<int>(0, (sum, x) => sum + x),
    v2AggregatesCount:
        v2AggregateCounts.values.fold<int>(0, (sum, x) => sum + x),
  );
}

String parityMismatchReason({
  required bool countMatch,
  required bool identityMatch,
  required bool moodMatch,
  required bool aggregateMatch,
}) {
  final mismatches = <String>[
    if (!countMatch) 'count',
    if (!identityMatch) 'identity',
    if (!moodMatch) 'mood',
    if (!aggregateMatch) 'aggregate',
  ];
  if (mismatches.isEmpty) {
    return '';
  }
  if (mismatches.length == 1) {
    return mismatches.first;
  }
  return 'mixed';
}

Map<String, int> _buildV1RegularCounts(List<Map<String, dynamic>> lessons) {
  final out = <String, int>{};
  for (final item in lessons) {
    final value = _string(item['grade_value']);
    if (value.isEmpty) {
      continue;
    }
    final key =
        'regular|${_normalizeToken(item['subject_name'])}|${_extractYmd(item['date'])}|$value';
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

Map<String, int> _buildV2RegularCounts(List<dynamic> results) {
  final out = <String, int>{};
  for (final raw in results.whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    if (_normalizeResultKind(item['result_kind']) != 'regular') {
      continue;
    }
    final date = _extractYmd(item['recorded_on']);
    final value = _string(item['value_text']);
    if (date.isEmpty || value.isEmpty) {
      continue;
    }
    final key = 'regular|${_normalizeToken(item['subject_name'])}|$date|$value';
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

Map<String, int> _buildV1SummativeCounts(
  List<dynamic> grades,
  String windowFrom,
  String windowTo,
) {
  final out = <String, int>{};
  for (final raw in grades.whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    final kind = _normalizeResultKind(item['grade_type']);
    if (kind != 'sor' && kind != 'soch') {
      continue;
    }
    final date = _extractYmd(item['created_at']);
    if (!_isInWindow(date, windowFrom, windowTo)) {
      continue;
    }
    final value = _string(item['value']);
    if (value.isEmpty) {
      continue;
    }
    final key = '$kind|*|$date|$value';
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

Map<String, int> _buildV2SummativeCounts(List<dynamic> results) {
  final out = <String, int>{};
  for (final raw in results.whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    final kind = _normalizeResultKind(item['result_kind']);
    if (kind != 'sor' && kind != 'soch') {
      continue;
    }
    final date = _extractYmd(item['recorded_on']);
    final value = _string(item['value_text']);
    if (date.isEmpty || value.isEmpty) {
      continue;
    }
    final key = '$kind|*|$date|$value';
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

Map<String, int> _buildV1AggregateCounts(
  List<dynamic> grades,
  String windowFrom,
  String windowTo,
) {
  final out = <String, int>{};
  for (final raw in grades.whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    final kind = _normalizeResultKind(item['grade_type']);
    if (kind != 'term' && kind != 'year') {
      continue;
    }
    final date = _extractYmd(item['created_at']);
    if (!_isInWindow(date, windowFrom, windowTo)) {
      continue;
    }
    final value = _string(item['value']);
    if (value.isEmpty) {
      continue;
    }
    final key = '$kind|${_normalizeToken(item['subject_name'])}|$date|$value';
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

Map<String, int> _buildV2AggregateCounts(List<dynamic> aggregates) {
  final out = <String, int>{};
  for (final raw in aggregates.whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    final kind = _normalizeResultKind(item['result_kind']);
    if (kind != 'term' && kind != 'year') {
      continue;
    }
    final date = _extractYmd(item['recorded_on']);
    final value = _string(item['value_text']);
    if (date.isEmpty || value.isEmpty) {
      continue;
    }
    final key = '$kind|${_normalizeToken(item['subject_name'])}|$date|$value';
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

Map<String, int> _buildV1AttendanceStatusMap(List<Map<String, dynamic>> rows) {
  final out = <String, int>{};
  for (final item in rows) {
    final date = _extractYmd(item['date']);
    if (date.isEmpty) {
      continue;
    }
    final status = _normalizeAttendanceStatus(item['code']);
    final key = '$date|$status';
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

Map<String, int> _buildV2AttendanceStatusMap(List<dynamic> rows) {
  final out = <String, int>{};
  for (final raw in rows.whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    final date = _extractYmd(item['recorded_on']);
    if (date.isEmpty) {
      continue;
    }
    final status = _normalizeAttendanceStatus(item['normalized_status']);
    final key = '$date|$status';
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

bool _hasAmbiguousRegularIdentity(
  Map<String, int> v1RegularCounts,
  List<dynamic> v2Results,
) {
  final refsByKey = <String, List<_RegularV2Ref>>{};
  for (final raw in v2Results.whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    if (_normalizeResultKind(item['result_kind']) != 'regular') {
      continue;
    }
    final date = _extractYmd(item['recorded_on']);
    final value = _string(item['value_text']);
    if (date.isEmpty || value.isEmpty) {
      continue;
    }
    final key = 'regular|${_normalizeToken(item['subject_name'])}|$date|$value';
    refsByKey.putIfAbsent(key, () => <_RegularV2Ref>[]).add(
          _RegularV2Ref(
            providerWorkId: _string(item['provider_work_id']),
            providerMarkId: _string(item['provider_mark_id']),
          ),
        );
  }

  for (final entry in v1RegularCounts.entries) {
    if (entry.value <= 1) {
      continue;
    }
    final refs = refsByKey[entry.key] ?? const <_RegularV2Ref>[];
    if (refs.length != entry.value) {
      return true;
    }
    final uniqueRefs = refs
        .map((item) => item.providerMarkId.isNotEmpty
            ? 'mark:${item.providerMarkId}'
            : item.providerWorkId.isNotEmpty
                ? 'work:${item.providerWorkId}'
                : '')
        .where((item) => item.isNotEmpty)
        .toSet();
    if (uniqueRefs.length != entry.value) {
      return true;
    }
  }
  return false;
}

bool _compareMoodMaps({
  required List<Map<String, dynamic>> v1Lessons,
  required List<dynamic> v1Grades,
  required List<dynamic> v2Results,
  required String windowFrom,
  required String windowTo,
}) {
  final v1Moods = <String, Map<String, int>>{};
  for (final lesson in v1Lessons) {
    final value = _string(lesson['grade_value']);
    if (value.isEmpty) {
      continue;
    }
    final key =
        'regular|${_normalizeToken(lesson['subject_name'])}|${_extractYmd(lesson['date'])}|$value';
    final mood = _normalizeMood(lesson['grade_mood']);
    v1Moods.putIfAbsent(key, () => <String, int>{});
    v1Moods[key]![mood] = (v1Moods[key]![mood] ?? 0) + 1;
  }
  for (final raw in v1Grades.whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    final kind = _normalizeResultKind(item['grade_type']);
    if (kind != 'sor' && kind != 'soch') {
      continue;
    }
    final date = _extractYmd(item['created_at']);
    if (!_isInWindow(date, windowFrom, windowTo)) {
      continue;
    }
    final value = _string(item['value']);
    if (value.isEmpty) {
      continue;
    }
    final key = '$kind|*|$date|$value';
    final mood = _normalizeMood(item['mood']);
    v1Moods.putIfAbsent(key, () => <String, int>{});
    v1Moods[key]![mood] = (v1Moods[key]![mood] ?? 0) + 1;
  }

  final v2Moods = <String, Map<String, int>>{};
  for (final raw in v2Results.whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    final kind = _normalizeResultKind(item['result_kind']);
    final date = _extractYmd(item['recorded_on']);
    final value = _string(item['value_text']);
    if (date.isEmpty || value.isEmpty) {
      continue;
    }
    final key = kind == 'regular'
        ? 'regular|${_normalizeToken(item['subject_name'])}|$date|$value'
        : (kind == 'sor' || kind == 'soch')
            ? '$kind|*|$date|$value'
            : '';
    if (key.isEmpty) {
      continue;
    }
    final mood = _normalizeMood(item['resolved_mood']);
    v2Moods.putIfAbsent(key, () => <String, int>{});
    v2Moods[key]![mood] = (v2Moods[key]![mood] ?? 0) + 1;
  }
  return _nestedIntMapEquals(v1Moods, v2Moods);
}

List<Map<String, dynamic>> _filterRowsByDate(
  List<dynamic> rows,
  String windowFrom,
  String windowTo,
) {
  return rows
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .where((item) {
    final date = _extractYmd(item['date']);
    return _isInWindow(date, windowFrom, windowTo);
  }).toList(growable: false);
}

bool _isInWindow(String ymd, String windowFrom, String windowTo) {
  if (ymd.isEmpty || windowFrom.isEmpty || windowTo.isEmpty) {
    return false;
  }
  return ymd.compareTo(windowFrom) >= 0 && ymd.compareTo(windowTo) <= 0;
}

bool _intMapEquals(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

bool _nestedIntMapEquals(
  Map<String, Map<String, int>> a,
  Map<String, Map<String, int>> b,
) {
  if (a.length != b.length) {
    return false;
  }
  for (final key in a.keys) {
    final left = a[key];
    final right = b[key];
    if (left == null || right == null || !_intMapEquals(left, right)) {
      return false;
    }
  }
  return true;
}

String _normalizeResultKind(Object? value) {
  final raw = _normalizeToken(value);
  if (raw.isEmpty) {
    return 'regular';
  }
  return raw;
}

String _normalizeToken(Object? value) {
  return _string(value).toLowerCase();
}

String _normalizeMood(Object? value) {
  final raw = _normalizeToken(value);
  if (raw.isEmpty) {
    return 'unknown';
  }
  return raw;
}

String _normalizeAttendanceStatus(Object? value) {
  final raw = _normalizeToken(value);
  switch (raw) {
    case 'present':
    case 'p':
    case '+':
    case 'п':
      return 'present';
    case 'absent':
    case 'a':
    case 'н':
      return 'absent';
    case 'late':
    case 'l':
    case 'о':
      return 'late';
    case 'excused':
    case 'e':
    case 'б':
      return 'excused';
    default:
      return 'unknown';
  }
}

bool _profileFieldMismatch(String left, String right) {
  final normalizedLeft = _normalizeProfileField(left);
  final normalizedRight = _normalizeProfileField(right);
  if (normalizedLeft.isEmpty || normalizedRight.isEmpty) {
    return false;
  }
  return normalizedLeft != normalizedRight;
}

String _normalizeProfileField(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp("[\"']"), '')
      .trim();
}

String _extractYmd(Object? value) {
  final raw = _string(value);
  if (raw.isEmpty) {
    return '';
  }
  final direct = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (direct.hasMatch(raw)) {
    return raw;
  }
  final fromIso = DateTime.tryParse(raw);
  if (fromIso != null) {
    return fromIso.toUtc().toIso8601String().split('T').first;
  }
  final inline = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(raw);
  if (inline != null) {
    return inline.group(1) ?? '';
  }
  return '';
}

String _string(Object? value) => (value ?? '').toString().trim();
