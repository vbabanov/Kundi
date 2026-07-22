import '../../homework/domain/homework_progress.dart';
import 'lessons_entity.dart';

class HomeGamificationMetrics {
  const HomeGamificationMetrics({
    required this.homeworkToday,
    required this.homeworkWeek,
    required this.attendance,
  });

  final HomeProgressMetric homeworkToday;
  final HomeProgressMetric homeworkWeek;
  final HomeProgressMetric attendance;

  factory HomeGamificationMetrics.fromLessons({
    required Iterable<LessonsEntity> lessons,
    required DateTime now,
  }) {
    final currentDay = _dateOnly(now);
    final weekStart = workweekStart(currentDay);
    final weekEnd = weekStart.add(const Duration(days: 4));
    final uniqueHomework = <String, LessonsEntity>{};
    final uniqueLessons = <String, _LessonAttendance>{};

    for (final lesson in lessons) {
      final lessonDate = parseLessonDate(lesson.date);
      if (lessonDate == null) {
        continue;
      }

      if (hasAssignedHomework(lesson)) {
        final key = homeworkIdentity(lesson);
        uniqueHomework.putIfAbsent(key, () => lesson);
      }

      if (!lessonDate.isAfter(currentDay) &&
          !lessonDate.isBefore(weekStart) &&
          !lessonDate.isAfter(weekEnd)) {
        final key = lessonIdentity(lesson);
        uniqueLessons.update(
          key,
          (current) => current.merge(lesson),
          ifAbsent: () => _LessonAttendance.fromLesson(lesson),
        );
      }
    }

    final todayHomework = uniqueHomework.values.where(
      (lesson) => sameDay(parseLessonDate(lesson.date), currentDay),
    );
    final weekHomework = uniqueHomework.values.where((lesson) {
      final lessonDate = parseLessonDate(lesson.date);
      return lessonDate != null &&
          !lessonDate.isBefore(weekStart) &&
          !lessonDate.isAfter(weekEnd);
    });

    return HomeGamificationMetrics(
      homeworkToday: _homeworkMetric(todayHomework),
      homeworkWeek: _homeworkMetric(weekHomework),
      attendance: _attendanceMetric(uniqueLessons.values),
    );
  }
}

class HomeProgressMetric {
  const HomeProgressMetric({
    required this.total,
    required this.completed,
    required this.emptyLabel,
  });

  final int total;
  final int completed;
  final String emptyLabel;

  int? get percent => total == 0 ? null : percentage(completed, total);
}

HomeProgressMetric _homeworkMetric(Iterable<LessonsEntity> lessons) {
  final items = lessons.toList(growable: false);
  return HomeProgressMetric(
    total: items.length,
    completed: items.where(isHomeworkCompleted).length,
    emptyLabel: 'Нет заданий',
  );
}

HomeProgressMetric _attendanceMetric(Iterable<_LessonAttendance> lessons) {
  final items = lessons.toList(growable: false);
  return HomeProgressMetric(
    total: items.length,
    completed: items.where((lesson) => !lesson.isAbsent).length,
    emptyLabel: 'Нет уроков',
  );
}

int percentage(int completed, int total) {
  if (total <= 0) {
    return 0;
  }
  final clampedCompleted = completed.clamp(0, total);
  return ((clampedCompleted / total) * 100).round().clamp(0, 100);
}

DateTime workweekStart(DateTime date) {
  final currentDay = _dateOnly(date);
  return currentDay
      .subtract(Duration(days: currentDay.weekday - DateTime.monday));
}

DateTime? parseLessonDate(String raw) {
  final parsed = DateTime.tryParse(raw.trim());
  return parsed == null ? null : _dateOnly(parsed);
}

bool sameDay(DateTime? left, DateTime right) {
  return left != null &&
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String lessonIdentity(LessonsEntity lesson) {
  final id = lesson.id.trim();
  if (id.isNotEmpty) {
    return id;
  }
  return '${lesson.date.trim()}|${lesson.lessonNumber}|'
      '${lesson.subjectName.trim().toLowerCase()}';
}

bool isAbsentAttendanceCode(String raw) {
  final code = raw.trim().toUpperCase();
  return code == 'Н' || code == 'Б';
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

class _LessonAttendance {
  const _LessonAttendance({required this.isAbsent});

  factory _LessonAttendance.fromLesson(LessonsEntity lesson) {
    return _LessonAttendance(
      isAbsent: isAbsentAttendanceCode(lesson.attendanceCode),
    );
  }

  final bool isAbsent;

  _LessonAttendance merge(LessonsEntity lesson) {
    return _LessonAttendance(
      isAbsent: isAbsent || isAbsentAttendanceCode(lesson.attendanceCode),
    );
  }
}
