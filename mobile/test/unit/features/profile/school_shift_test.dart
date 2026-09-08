import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/profile/domain/school_shift.dart';

void main() {
  final reference = DateTime(2026, 9, 8);

  ShiftLesson lesson(String date, int number, String startTime) => ShiftLesson(
        date: date,
        lessonNumber: number,
        startTime: startTime,
      );

  test('08:00 regular lesson derives first shift', () {
    expect(
      deriveSchoolShift(
        [lesson('2026-09-08', 1, '08:00')],
        referenceDate: reference,
      ),
      SchoolShift.first,
    );
  });

  test('zero lesson at 13:00 does not hide second-shift anchor', () {
    expect(
      deriveSchoolShift(
        [
          lesson('2026-09-08', 0, '13:00'),
          lesson('2026-09-08', 1, '14:00'),
        ],
        referenceDate: reference,
      ),
      SchoolShift.second,
    );
  });

  test('zero-only day is ignored when another day has a morning anchor', () {
    expect(
      deriveSchoolShift(
        [
          lesson('2026-09-08', 0, '13:00'),
          lesson('2026-09-09', 1, '08:00'),
        ],
        referenceDate: reference,
      ),
      SchoolShift.first,
    );
  });

  test('14:00 boundary derives second shift', () {
    expect(
      deriveSchoolShift(
        [lesson('2026-09-08', 1, '14:00')],
        referenceDate: reference,
      ),
      SchoolShift.second,
    );
  });

  test('no regular lessons yields unknown instead of guessing', () {
    expect(
      deriveSchoolShift(
        [lesson('2026-09-08', 0, '13:00')],
        referenceDate: reference,
      ),
      SchoolShift.unknown,
    );
  });

  test('strict majority across nearest five usable days wins', () {
    expect(
      deriveSchoolShift(
        [
          lesson('2026-09-06', 1, '08:00'),
          lesson('2026-09-07', 1, '14:00'),
          lesson('2026-09-08', 1, '08:00'),
          lesson('2026-09-09', 1, '14:00'),
          lesson('2026-09-10', 1, '14:00'),
          lesson('2026-09-11', 1, '08:00'),
        ],
        referenceDate: reference,
      ),
      SchoolShift.second,
    );
  });

  test('tie resolves to nearest usable day, future before equally near past',
      () {
    expect(
      deriveSchoolShift(
        [
          lesson('2026-09-07', 1, '08:00'),
          lesson('2026-09-09', 1, '14:00'),
        ],
        referenceDate: reference,
      ),
      SchoolShift.second,
    );
  });

  test('lowest positive lesson number is the daily anchor', () {
    expect(
      deriveSchoolShift(
        [
          lesson('2026-09-08', 2, '08:00'),
          lesson('2026-09-08', 1, '14:10'),
        ],
        referenceDate: reference,
      ),
      SchoolShift.second,
    );
  });
}
