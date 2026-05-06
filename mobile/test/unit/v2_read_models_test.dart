import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/network/v2_read_models.dart';

void main() {
  test('parses v2 profile with provider/local split', () {
    final dto = V2ProfileResponse.fromJson({
      'window': {
        'provider': 'kundelik',
        'window_from': '2026-03-01',
        'window_to': '2026-03-31',
        'snapshot_at': '2026-04-01T10:00:00Z',
        'window_key': 'kundelik:2026-03-01:2026-03-31',
      },
      'provider_identity': {
        'provider': 'kundelik',
        'provider_person_id': 'p1',
        'provider_school_id': 's1',
        'provider_group_id': 'g1',
        'provider_account_ref': 'acc',
        'student_full_name': 'Artem Example',
        'school_name': 'School',
        'class_label': '7Ж',
        'class_teacher_full_name': 'Teacher',
      },
      'local_app_profile': {
        'shift': 2,
        'parent_phone_1': '+7701',
        'parent_phone_2': '+7702',
      },
    });

    expect(dto.window.windowKey, 'kundelik:2026-03-01:2026-03-31');
    expect(dto.providerIdentity.providerSchoolId, 's1');
    expect(dto.localAppProfile?.shift, 2);
  });

  test('parses typed v2 results payload', () {
    final dto = V2ResultsResponse.fromJson({
      'window': {
        'provider': 'kundelik',
        'window_from': '2026-03-01',
        'window_to': '2026-03-31',
        'snapshot_at': '2026-04-01T10:00:00Z',
        'window_key': 'kundelik:2026-03-01:2026-03-31',
      },
      'lessons': [
        {
          'lesson_id': 'l1',
          'provider': 'kundelik',
          'provider_lesson_id': 'pl1',
          'provider_subject_id': 'sub1',
          'lesson_date': '2026-03-10',
          'lesson_number': 2,
          'subject_name': 'Math',
          'lesson_place': '312',
          'start_time': '08:30',
          'end_time': '09:15',
          'theme': 'Linear equations',
          'homework_text': 'Solve 1-10',
          'homework_status': 'assigned',
        },
      ],
      'results': [
        {
          'result_id': 'r1',
          'provider': 'kundelik',
          'result_kind': 'regular',
          'provider_work_id': 'w1',
          'provider_mark_id': 'm1',
          'provider_subject_id': 'sub1',
          'subject_name': 'Math',
          'value_text': '5',
          'resolved_mood': 'good',
          'recorded_on': '2026-03-10',
          'source_endpoint': 'diary',
          'source_mood_raw': 'good',
        },
      ],
      'aggregates': [
        {
          'aggregate_id': 'a1',
          'provider': 'kundelik',
          'result_kind': 'term',
          'provider_subject_id': 'sub1',
          'subject_name': 'Math',
          'value_text': '4',
          'resolved_mood': 'neutral',
          'recorded_on': '2026-03-30',
          'term_no': 3,
          'year_label': '',
        },
      ],
      'attendance': [
        {
          'attendance_id': 'att1',
          'provider': 'kundelik',
          'provider_event_key': 'evt1',
          'provider_lesson_ref': 'pl1',
          'recorded_on': '2026-03-10',
          'raw_code': 'Н',
          'normalized_status': 'absent',
          'reason': 'ill',
        },
      ],
    });

    expect(dto.window.snapshotAt, '2026-04-01T10:00:00Z');
    expect(dto.lessons.single.lessonId, 'l1');
    expect(dto.lessons.single.lessonNumber, 2);
    expect(dto.lessons.single.lessonPlace, '312');
    expect(dto.results.single.resultId, 'r1');
    expect(dto.aggregates.single.aggregateId, 'a1');
    expect(dto.attendance.single.normalizedStatus, 'absent');
  });

  test('parses typed v2 overview payload', () {
    final dto = V2OverviewResponse.fromJson({
      'window': {
        'provider': 'kundelik',
        'window_from': '2026-03-01',
        'window_to': '2026-03-31',
        'snapshot_at': '2026-04-01T10:00:00Z',
        'window_key': 'kundelik:2026-03-01:2026-03-31',
      },
      'provider_identity': {
        'provider': 'kundelik',
        'provider_account_ref': 'acc',
        'provider_person_id': 'p1',
        'provider_school_id': 's1',
        'provider_group_id': 'g1',
        'student_full_name': 'Artem Example',
        'school_name': 'School',
        'class_label': '7Р–',
        'class_teacher_full_name': 'Teacher',
      },
      'local_app_profile': {
        'shift': '2',
        'parent_phone_1': '+7701',
        'parent_phone_2': '+7702',
      },
      'counts': {
        'lessons_in_window': 12,
        'results_in_window': 10,
        'aggregates_in_window': 4,
        'attendance_alerts': 1,
      },
      'highlights': {
        'recent_results': [
          {
            'result_id': 'r1',
            'result_kind': 'regular',
            'subject_name': 'Math',
            'value_text': '5',
            'recorded_on': '2026-03-10',
            'resolved_mood': 'good',
          },
        ],
        'upcoming_lessons': [
          {
            'lesson_id': 'l2',
            'lesson_date': '2026-03-20',
            'lesson_number': 1,
            'subject_name': 'Physics',
            'theme': 'Forces',
            'homework_text': 'Read chapter 2',
          },
        ],
      },
    });

    expect(dto.counts.lessonsInWindow, 12);
    expect(dto.highlights.recentResults.single.resultId, 'r1');
    expect(dto.highlights.upcomingLessons.single.lessonId, 'l2');
    expect(dto.rawHighlights['recent_results'], isA<List<dynamic>>());
  });

  test('throws format exception for missing required map', () {
    expect(
      () => V2ResultsResponse.fromJson({
        'results': [],
        'lessons': [],
        'aggregates': [],
        'attendance': [],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('throws format exception for invalid list payload element', () {
    expect(
      () => V2ResultsResponse.fromJson({
        'window': {
          'provider': 'kundelik',
          'window_from': '2026-03-01',
          'window_to': '2026-03-31',
          'snapshot_at': '2026-04-01T10:00:00Z',
          'window_key': 'kundelik:2026-03-01:2026-03-31',
        },
        'lessons': ['invalid'],
        'results': [],
        'aggregates': [],
        'attendance': [],
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
