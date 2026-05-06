import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/auth/data/academic_year_window.dart';

void main() {
  test('academic year starts at Sep 1 of current year when month >= 9', () {
    final window = AcademicYearWindow.forNowUtc(DateTime.utc(2026, 11, 15));
    expect(window.windowFrom, '2026-09-01');
    expect(window.windowTo, '2026-11-15');
  });

  test('academic year starts at Sep 1 of previous year when month < 9', () {
    final window = AcademicYearWindow.forNowUtc(DateTime.utc(2026, 4, 5));
    expect(window.windowFrom, '2025-09-01');
    expect(window.windowTo, '2026-04-05');
  });
}
