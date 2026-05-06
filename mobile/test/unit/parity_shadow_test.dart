import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/auth/data/parity_shadow.dart';

void main() {
  const windowFrom = '2026-03-01';
  const windowTo = '2026-03-31';

  Map<String, dynamic> baseV1Profile() => <String, dynamic>{
        'class_label': '7Ж',
        'school_name': 'School 1',
      };

  Map<String, dynamic> baseV2Identity() => <String, dynamic>{
        'provider': 'kundelik',
        'class_label': '7Ж',
        'school_name': 'School 1',
      };

  test('parity shadow reports full match when datasets align', () {
    final outcome = evaluateTypedReadParityShadow(
      v1Profile: baseV1Profile(),
      v1Grades: <dynamic>[
        <String, dynamic>{
          'grade_type': 'sor',
          'created_at': '2026-03-10',
          'value': '10',
          'mood': 'good',
        },
        <String, dynamic>{
          'grade_type': 'term',
          'created_at': '2026-03-30',
          'value': '4',
          'subject_name': 'Math',
        },
      ],
      v1Lessons: <dynamic>[
        <String, dynamic>{
          'date': '2026-03-10',
          'subject_name': 'Math',
          'grade_value': '5',
          'grade_mood': 'good',
        },
      ],
      v1Attendance: <dynamic>[
        <String, dynamic>{'date': '2026-03-10', 'code': 'Н'},
      ],
      v2Identity: baseV2Identity(),
      v2Results: <dynamic>[
        <String, dynamic>{
          'result_kind': 'regular',
          'recorded_on': '2026-03-10',
          'subject_name': 'Math',
          'value_text': '5',
          'resolved_mood': 'good',
          'provider_work_id': 'w1',
          'provider_mark_id': 'm1',
        },
        <String, dynamic>{
          'result_kind': 'sor',
          'recorded_on': '2026-03-10',
          'value_text': '10',
          'resolved_mood': 'good',
        },
      ],
      v2Lessons: <dynamic>[
        <String, dynamic>{'lesson_id': 'l1'},
      ],
      v2Aggregates: <dynamic>[
        <String, dynamic>{
          'result_kind': 'term',
          'recorded_on': '2026-03-30',
          'subject_name': 'Math',
          'value_text': '4',
        },
      ],
      v2Attendance: <dynamic>[
        <String, dynamic>{
          'recorded_on': '2026-03-10',
          'normalized_status': 'absent',
        },
      ],
      windowFrom: windowFrom,
      windowTo: windowTo,
    );

    expect(outcome.countMatch, isTrue);
    expect(outcome.identityMatch, isTrue);
    expect(outcome.moodMatch, isTrue);
    expect(outcome.aggregateMatch, isTrue);
    expect(outcome.mismatchReason, isEmpty);
  });

  test('parity shadow flags mood mismatch explicitly', () {
    final outcome = evaluateTypedReadParityShadow(
      v1Profile: baseV1Profile(),
      v1Grades: const <dynamic>[],
      v1Lessons: <dynamic>[
        <String, dynamic>{
          'date': '2026-03-10',
          'subject_name': 'Math',
          'grade_value': '5',
          'grade_mood': 'good',
        },
      ],
      v1Attendance: const <dynamic>[],
      v2Identity: baseV2Identity(),
      v2Results: <dynamic>[
        <String, dynamic>{
          'result_kind': 'regular',
          'recorded_on': '2026-03-10',
          'subject_name': 'Math',
          'value_text': '5',
          'resolved_mood': 'bad',
          'provider_work_id': 'w1',
          'provider_mark_id': 'm1',
        },
      ],
      v2Lessons: <dynamic>[
        <String, dynamic>{'lesson_id': 'l1'},
      ],
      v2Aggregates: const <dynamic>[],
      v2Attendance: const <dynamic>[],
      windowFrom: windowFrom,
      windowTo: windowTo,
    );

    expect(outcome.identityMatch, isTrue);
    expect(outcome.moodMatch, isFalse);
    expect(outcome.mismatchReason, 'mood');
  });

  test('parity shadow flags aggregate mismatch', () {
    final outcome = evaluateTypedReadParityShadow(
      v1Profile: baseV1Profile(),
      v1Grades: <dynamic>[
        <String, dynamic>{
          'grade_type': 'year',
          'created_at': '2026-03-30',
          'value': '5',
          'subject_name': 'Math',
        },
      ],
      v1Lessons: const <dynamic>[],
      v1Attendance: const <dynamic>[],
      v2Identity: baseV2Identity(),
      v2Results: const <dynamic>[],
      v2Lessons: const <dynamic>[],
      v2Aggregates: <dynamic>[
        <String, dynamic>{
          'result_kind': 'year',
          'recorded_on': '2026-03-30',
          'subject_name': 'Math',
          'value_text': '4',
        },
      ],
      v2Attendance: const <dynamic>[],
      windowFrom: windowFrom,
      windowTo: windowTo,
    );

    expect(outcome.aggregateMatch, isFalse);
    expect(outcome.mismatchReason, 'aggregate');
  });

  test('parity shadow flags attendance status mismatch as identity mismatch',
      () {
    final outcome = evaluateTypedReadParityShadow(
      v1Profile: baseV1Profile(),
      v1Grades: const <dynamic>[],
      v1Lessons: const <dynamic>[],
      v1Attendance: <dynamic>[
        <String, dynamic>{'date': '2026-03-10', 'code': 'Н'},
      ],
      v2Identity: baseV2Identity(),
      v2Results: const <dynamic>[],
      v2Lessons: const <dynamic>[],
      v2Aggregates: const <dynamic>[],
      v2Attendance: <dynamic>[
        <String, dynamic>{
          'recorded_on': '2026-03-10',
          'normalized_status': 'present',
        },
      ],
      windowFrom: windowFrom,
      windowTo: windowTo,
    );

    expect(outcome.attendanceStatusMatch, isFalse);
    expect(outcome.identityMatch, isFalse);
    expect(outcome.mismatchReason, 'identity');
  });

  test('parity shadow avoids false OK on ambiguous duplicate regulars', () {
    final outcome = evaluateTypedReadParityShadow(
      v1Profile: baseV1Profile(),
      v1Grades: const <dynamic>[],
      v1Lessons: <dynamic>[
        <String, dynamic>{
          'date': '2026-03-10',
          'subject_name': 'Math',
          'grade_value': '5',
          'grade_mood': 'good',
        },
        <String, dynamic>{
          'date': '2026-03-10',
          'subject_name': 'Math',
          'grade_value': '5',
          'grade_mood': 'good',
        },
      ],
      v1Attendance: const <dynamic>[],
      v2Identity: baseV2Identity(),
      v2Results: <dynamic>[
        <String, dynamic>{
          'result_kind': 'regular',
          'recorded_on': '2026-03-10',
          'subject_name': 'Math',
          'value_text': '5',
          'resolved_mood': 'good',
          'provider_work_id': '',
          'provider_mark_id': '',
        },
        <String, dynamic>{
          'result_kind': 'regular',
          'recorded_on': '2026-03-10',
          'subject_name': 'Math',
          'value_text': '5',
          'resolved_mood': 'good',
          'provider_work_id': '',
          'provider_mark_id': '',
        },
      ],
      v2Lessons: <dynamic>[
        <String, dynamic>{'lesson_id': 'l1'},
        <String, dynamic>{'lesson_id': 'l2'},
      ],
      v2Aggregates: const <dynamic>[],
      v2Attendance: const <dynamic>[],
      windowFrom: windowFrom,
      windowTo: windowTo,
    );

    expect(outcome.countMatch, isTrue);
    expect(outcome.identityMatch, isFalse);
    expect(outcome.mismatchReason, 'identity');
  });
}
