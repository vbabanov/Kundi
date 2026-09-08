enum SchoolShift {
  unknown,
  first,
  second;

  int? get number => switch (this) {
        SchoolShift.first => 1,
        SchoolShift.second => 2,
        SchoolShift.unknown => null,
      };
}

class ShiftLesson {
  const ShiftLesson({
    required this.date,
    required this.lessonNumber,
    required this.startTime,
  });

  final String date;
  final int lessonNumber;
  final String startTime;
}

/// Derives a school shift from up to [maxSchoolDays] nearest usable days.
///
/// Each day contributes one vote using the lowest regular lesson number
/// (`lessonNumber > 0`); zero lessons never act as anchors. An anchor starting
/// before 14:00 votes for the first shift, otherwise for the second. A strict
/// majority wins. If an even split remains, the nearest usable day wins;
/// equally distant future days sort before past days. With no valid regular
/// anchor the result is unknown.
SchoolShift deriveSchoolShift(
  Iterable<ShiftLesson> lessons, {
  DateTime? referenceDate,
  int maxSchoolDays = 5,
}) {
  if (maxSchoolDays <= 0) {
    return SchoolShift.unknown;
  }
  final reference = _dateOnly(referenceDate ?? DateTime.now());
  final byDate = <DateTime, List<ShiftLesson>>{};
  for (final lesson in lessons) {
    if (lesson.lessonNumber <= 0) {
      continue;
    }
    final date = _parseDate(lesson.date);
    if (date == null) {
      continue;
    }
    byDate.putIfAbsent(date, () => <ShiftLesson>[]).add(lesson);
  }

  final votes = <_DatedShift>[];
  for (final entry in byDate.entries) {
    final regular = List<ShiftLesson>.from(entry.value)
      ..sort((a, b) {
        final numberOrder = a.lessonNumber.compareTo(b.lessonNumber);
        if (numberOrder != 0) return numberOrder;
        return a.startTime.compareTo(b.startTime);
      });
    final firstNumber = regular.first.lessonNumber;
    final anchors = regular.where((item) => item.lessonNumber == firstNumber);
    final startMinutes = anchors
        .map((item) => _parseMinutes(item.startTime))
        .whereType<int>()
        .fold<int?>(null, (earliest, value) {
      if (earliest == null || value < earliest) return value;
      return earliest;
    });
    if (startMinutes == null) {
      continue;
    }
    votes.add(
      _DatedShift(
        date: entry.key,
        shift: startMinutes < 14 * 60 ? SchoolShift.first : SchoolShift.second,
      ),
    );
  }
  votes.sort((a, b) {
    final aDistance = a.date.difference(reference).inDays.abs();
    final bDistance = b.date.difference(reference).inDays.abs();
    final distanceOrder = aDistance.compareTo(bDistance);
    if (distanceOrder != 0) return distanceOrder;
    final aFuture = !a.date.isBefore(reference);
    final bFuture = !b.date.isBefore(reference);
    if (aFuture != bFuture) return aFuture ? -1 : 1;
    return a.date.compareTo(b.date);
  });
  final nearest = votes.take(maxSchoolDays).toList(growable: false);
  if (nearest.isEmpty) {
    return SchoolShift.unknown;
  }
  final firstCount =
      nearest.where((item) => item.shift == SchoolShift.first).length;
  final secondCount = nearest.length - firstCount;
  if (firstCount > secondCount) return SchoolShift.first;
  if (secondCount > firstCount) return SchoolShift.second;
  return nearest.first.shift;
}

class _DatedShift {
  const _DatedShift({required this.date, required this.shift});

  final DateTime date;
  final SchoolShift shift;
}

DateTime? _parseDate(String raw) {
  final normalized = raw.trim();
  if (normalized.length < 10) return null;
  final parsed = DateTime.tryParse(normalized.substring(0, 10));
  return parsed == null ? null : _dateOnly(parsed);
}

int? _parseMinutes(String raw) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw.trim());
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
