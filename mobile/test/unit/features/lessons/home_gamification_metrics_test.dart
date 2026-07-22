import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/lessons/domain/home_gamification_metrics.dart';
import 'package:kundi_mobile/features/lessons/domain/home_greeting.dart';
import 'package:kundi_mobile/features/lessons/domain/lessons_entity.dart';
import 'package:kundi_mobile/features/profile/domain/profile_entity.dart';

void main() {
  group('home greeting', () {
    test('uses local time ranges, russian date and first name', () {
      expect(homeGreetingFor(DateTime(2026, 7, 22, 5), 'Артем'),
          'Доброе утро, Артем');
      expect(homeGreetingFor(DateTime(2026, 7, 22, 12), 'Артем'),
          'Добрый день, Артем');
      expect(homeGreetingFor(DateTime(2026, 7, 22, 18), 'Артем'),
          'Добрый вечер, Артем');
      expect(homeGreetingFor(DateTime(2026, 7, 22, 23), 'Артем'),
          'Доброй ночи, Артем');
      expect(homeGreetingFor(DateTime(2026, 7, 22, 2), ''), 'Доброй ночи!');
      expect(russianDateLabel(DateTime(2026, 7, 22)), 'Среда, 22 июля');
      expect(
        resolveStudentFirstName(
          explicitFirstName: '',
          fullName: 'Бабанов Артем',
        ),
        'Артем',
      );
    });
  });

  group('home gamification metrics', () {
    test('calculates today homework and ignores empty homework', () {
      final metrics = _metrics([
        _lesson(id: '1', date: '2026-07-22', homework: 'a', grade: '5'),
        _lesson(id: '2', date: '2026-07-22', homework: 'b', grade: '5'),
        _lesson(id: '3', date: '2026-07-22', homework: 'c', grade: '5'),
        _lesson(id: '4', date: '2026-07-22', homework: 'd', grade: '5'),
        _lesson(id: 'empty', date: '2026-07-22', homework: '   '),
      ]);

      expect(metrics.homeworkToday.total, 4);
      expect(metrics.homeworkToday.completed, 4);
      expect(metrics.homeworkToday.percent, 100);
    });

    test('calculates partially completed today homework and empty state', () {
      final partial = _metrics([
        _lesson(id: '1', date: '2026-07-22', homework: 'a', grade: '5'),
        _lesson(id: '2', date: '2026-07-22', homework: 'b', grade: '4'),
        _lesson(id: '3', date: '2026-07-22', homework: 'c'),
        _lesson(id: '4', date: '2026-07-22', homework: 'd'),
      ]);
      final empty = _metrics([
        _lesson(id: 'empty', date: '2026-07-22', homework: ' '),
      ]);

      expect(partial.homeworkToday.percent, 50);
      expect(empty.homeworkToday.percent, isNull);
      expect(empty.homeworkToday.emptyLabel, 'Нет заданий');
    });

    test('keeps homework week to Monday through Friday without duplicates', () {
      final metrics = _metrics([
        _lesson(id: 'mon', date: '2026-07-20', homework: 'a', grade: '5'),
        _lesson(id: 'tue', date: '2026-07-21', homework: 'b'),
        _lesson(id: 'wed', date: '2026-07-22', homework: 'c', grade: '4'),
        _lesson(id: 'wed', date: '2026-07-22', homework: 'c', grade: '4'),
        _lesson(id: 'sat', date: '2026-07-25', homework: 'weekend', grade: '5'),
        _lesson(id: 'sun', date: '2026-07-26', homework: 'weekend', grade: '5'),
      ]);

      expect(metrics.homeworkWeek.total, 3);
      expect(metrics.homeworkWeek.completed, 2);
      expect(metrics.homeworkWeek.percent, 67);
    });

    test('calculates attendance from unique conducted weekday lessons', () {
      final metrics = _metrics([
        _lesson(id: 'grade', date: '2026-07-20', grade: '5'),
        _lesson(id: 'dot', date: '2026-07-21'),
        _lesson(id: 'absent-n', date: '2026-07-22', attendance: 'Н'),
        _lesson(id: 'absent-b', date: '2026-07-22', attendance: 'Б'),
        _lesson(id: 'grade', date: '2026-07-20', grade: '4'),
        _lesson(id: 'future', date: '2026-07-23'),
        _lesson(id: 'weekend', date: '2026-07-25'),
      ]);

      expect(metrics.attendance.total, 4);
      expect(metrics.attendance.completed, 2);
      expect(metrics.attendance.percent, 50);
    });

    test('uses dash state when no conducted lessons exist', () {
      final metrics = _metrics([
        _lesson(id: 'future', date: '2026-07-23'),
      ]);

      expect(metrics.attendance.percent, isNull);
      expect(metrics.attendance.emptyLabel, 'Нет уроков');
      expect(percentage(9, 4), 100);
    });
  });
}

HomeGamificationMetrics _metrics(List<LessonsEntity> lessons) {
  return HomeGamificationMetrics.fromLessons(
    lessons: lessons,
    now: DateTime(2026, 7, 22, 14),
  );
}

LessonsEntity _lesson({
  required String id,
  required String date,
  String homework = '',
  String grade = '',
  String attendance = '',
}) {
  return LessonsEntity(
    id: id,
    date: date,
    lessonNumber: 1,
    subjectName: 'Алгебра',
    topic: '',
    homeworkText: homework,
    requiresPhoto: false,
    gradeValue: grade,
    attendanceCode: attendance,
  );
}
