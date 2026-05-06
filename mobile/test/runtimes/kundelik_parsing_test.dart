import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/contracts/models.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/source_adapters/kundelik/kundelik_parsing.dart';

void main() {
  test('extractSourceIds parses ids from html', () {
    final html = '''
      <script>
        var personId = "12345";
        var schoolId=678;
        var groupId : "90";
      </script>
    ''';
    final ids = extractSourceIds(html);
    expect(ids['person_id'], '12345');
    expect(ids['school_id'], '678');
    expect(ids['group_id'], '90');
  });

  test('extractSourceIds prefers non-zero school id when zero is present', () {
    final html = '''
      <script>
        var personId = "1000016003118";
        var schoolId = 0;
        var somePayload = {"schoolId":"1000001828996"};
      </script>
      <a href="/school/1000001828996/person/1000016003118"></a>
    ''';
    final ids = extractSourceIds(html);
    expect(ids['person_id'], '1000016003118');
    expect(ids['school_id'], '1000001828996');
  });

  test('extractPeriodIdsFromMarksHtml collects numeric and final period ids',
      () {
    const html = '''
      <a href="/marks/school/100/student/200/period?periodId=2395845913549013990">1</a>
      <a href="/marks/school/100/student/200/period?periodId=2395845913549013991">2</a>
      <a href="/marks/school/100/student/200/period?periodId=final">Итог</a>
      <script>
        window.__bootstrap = {"periodId":"2395845913549013992"};
      </script>
    ''';
    final periodIds = extractPeriodIdsFromMarksHtml(html);
    expect(
      periodIds,
      containsAll(<String>[
        '2395845913549013990',
        '2395845913549013991',
        '2395845913549013992',
        'final',
      ]),
    );
  });

  test('extractPeriodIdsFromMarksPayload collects period ids from final works',
      () {
    final payload = {
      'periodId': 'final',
      'subjects': [
        {
          'finalWorks': [
            {'periodId': '2395845913549013990'},
            {'periodId': '2395845913549013991'},
          ]
        }
      ],
    };
    final periodIds = extractPeriodIdsFromMarksPayload(payload);
    expect(
      periodIds,
      containsAll(<String>[
        'final',
        '2395845913549013990',
        '2395845913549013991',
      ]),
    );
  });

  test('parseProfile builds grade-aware profile', () {
    const html = '''
      {"firstName":"Aruzhan","lastName":"K.","className":"7A","schoolName":"Kundi School"}
    ''';
    final profile = parseProfile(html, fallbackLogin: 'student-login');
    expect(profile.firstName, 'Aruzhan');
    expect(profile.gradeLevel, 7);
    expect(profile.classLabel, '7A');
    expect(profile.schoolName, 'Kundi School');
  });

  test('parseLessons parses lesson entries and grades', () {
    final payload = {
      'lessons': [
        {
          'id': 'l1',
          'date': '2026-03-30',
          'lessonNumber': 1,
          'subjectName': 'Math',
          'topic': 'Linear equations',
          'homework': 'Solve 1-10',
          'requiresPhoto': true,
          'grades': [
            {'id': 'g1', 'value': '5', 'type': 'regular'}
          ],
        }
      ],
    };

    final lessons = parseLessons(payload);
    expect(lessons.length, 1);
    expect(lessons.first.sourceLessonKey, 'l1');
    expect(lessons.first.subjectName, 'Math');
    expect(lessons.first.homeworkText, 'Solve 1-10');
    expect(lessons.first.requiresPhoto, true);
    expect(lessons.first.grades.length, 1);
    expect(lessons.first.grades.first.sourceGradeKey, 'g1');
  });

  test('parseLessons normalizes date and time for ingest contract', () {
    final payload = {
      'lessons': [
        {
          'id': 'l2',
          'date': '2026-03-30T00:00:00+05:00',
          'lessonNumber': 2,
          'subjectName': 'History',
          'startTime': '08:30:00',
          'endTime': '09:15:00',
          'grades': const [],
        }
      ],
    };

    final lessons = parseLessons(payload);
    expect(lessons, hasLength(1));
    expect(lessons.first.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(lessons.first.startTime, '08:30');
    expect(lessons.first.endTime, '09:15');
  });

  test('parseLessons flattens days.lessons using day date and workMarks', () {
    final payload = {
      'days': [
        {
          'date': '2026-03-31',
          'groupId': 42,
          'lessons': [
            {
              'id': 'l3',
              'lessonNumber': 3,
              'subject': {'name': 'Biology'},
              'theme': 'Plants',
              'homework': {'text': 'Read paragraph 2'},
              'workMarks': [
                {'id': 'wm1', 'value': '4', 'type': 'regular'}
              ],
            }
          ],
        }
      ],
    };

    final lessons = parseLessons(payload);
    expect(lessons, hasLength(1));
    expect(lessons.first.date, '2026-03-31');
    expect(lessons.first.subjectName, 'Biology');
    expect(lessons.first.homeworkText, 'Read paragraph 2');
    expect(lessons.first.grades, hasLength(1));
    expect(lessons.first.grades.first.value, '4');
  });

  test('normalizeKundelikDayDateToYmd converts unix seconds to YYYY-MM-DD', () {
    const rawSeconds = '1774979877';
    final expectedDate = DateTime.fromMillisecondsSinceEpoch(
      int.parse(rawSeconds) * 1000,
      isUtc: true,
    );
    final expected =
        '${expectedDate.year.toString().padLeft(4, '0')}-${expectedDate.month.toString().padLeft(2, '0')}-${expectedDate.day.toString().padLeft(2, '0')}';

    expect(normalizeKundelikDayDateToYmd(rawSeconds), expected);
  });

  test('canonical bundle payload normalizes lesson date from unix seconds', () {
    const rawSeconds = '1774979877';
    final bundle = CanonicalBundle(
      source: 'kundelik',
      sourceAccount: 'acc',
      idempotencyKey: 'mobile-12345678',
      syncedAt: DateTime.now().toUtc(),
      sourceIds: const {'person_id': '1', 'school_id': '2'},
      profile: const SourceProfile(
        firstName: 'A',
        lastName: 'B',
        gradeLevel: 6,
        classLabel: '6A',
        schoolName: 'School',
        classTeacherFullName: '',
      ),
      lessons: const [
        SourceLesson(
          sourceLessonKey: 'l1',
          date: rawSeconds,
          lessonNumber: 1,
          subjectName: 'Math',
          lessonPlace: '',
          startTime: '08:30:00',
          endTime: '09:15:00',
          topicTitle: 'Topic',
          homeworkText: 'HW',
          requiresPhoto: false,
          grades: [],
        ),
      ],
      attendance: const [],
    );

    final json = bundle.toJson();
    final lessons = json['lessons'] as List<dynamic>;
    final first = lessons.first as Map<String, dynamic>;
    expect(first['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(first['start_time'], '08:30');
    expect(first['end_time'], '09:15');
  });

  test('parseChatIdentity extracts school class and teacher jid', () {
    final payload = {
      'contacts': [
        {
          'schoolName': 'School 53',
          'classTeacher': 'user_42@xmpp.kundelik.kz',
          'groups': {
            '2370210495004756744': {'name': '7ж'}
          },
          'members': [
            {
              'personId': '1000016003118',
              'jid': 'user_1000016003118@xmpp.kundelik.kz',
            }
          ],
        }
      ],
    };

    final identity = parseChatIdentity(
      closeContactsRaw: payload,
      targetGroupId: '2370210495004756744',
      targetPersonId: '1000016003118',
    );
    expect(identity.schoolName, 'School 53');
    expect(identity.classLabel, '7ж');
    expect(identity.classTeacherJid, 'user_42@xmpp.kundelik.kz');
    expect(identity.studentJid, 'user_1000016003118@xmpp.kundelik.kz');
  });

  test(
      'parseChatIdentity binds schoolName to matched group/person contact, not first contact',
      () {
    final payload = {
      'contacts': [
        {
          'schoolName': 'Факультативные занятия',
          'classTeacher': 'user_999@xmpp.kundelik.kz',
          'groups': {
            'other_group': {'name': 'Факультатив'}
          },
          'members': [
            {
              'personId': 'other_person',
              'jid': 'user_111@xmpp.kundelik.kz',
            }
          ],
        },
        {
          'schoolName': 'Бауыржан Момышұлы ат. №53 мектеп-лицей',
          'classTeacher': 'user_42@xmpp.kundelik.kz',
          'groups': {
            '2370210495004756744': {'name': '7ж'}
          },
          'members': [
            {
              'personId': '1000016003118',
              'jid': 'user_1000016003118@xmpp.kundelik.kz',
            }
          ],
        },
      ],
    };

    final identity = parseChatIdentity(
      closeContactsRaw: payload,
      targetGroupId: '2370210495004756744',
      targetPersonId: '1000016003118',
    );
    expect(identity.schoolName, 'Бауыржан Момышұлы ат. №53 мектеп-лицей');
    expect(identity.classLabel, '7ж');
    expect(identity.classTeacherJid, 'user_42@xmpp.kundelik.kz');
    expect(identity.studentJid, 'user_1000016003118@xmpp.kundelik.kz');
  });

  test('parseEnrichNames maps jid to human names', () {
    final payload = {
      'data': {
        'user_42@xmpp.kundelik.kz': {'name': 'Teacher Name'},
        'user_1000016003118@xmpp.kundelik.kz': {'name': 'Student Name'},
      },
    };

    final names = parseEnrichNames(payload);
    expect(names['user_42@xmpp.kundelik.kz'], 'Teacher Name');
    expect(names['user_1000016003118@xmpp.kundelik.kz'], 'Student Name');
  });

  test('parsePeriodAcademicPayload extracts regular sor and term records', () {
    final payload = {
      'periodId': '2395845913549013991',
      'dateFinish': '1766707200',
      'subjects': [
        {
          'id': 'sub-1',
          'name': 'Math',
          'works': [
            {
              'workId': 'work-1',
              'date': '1762905600',
              'lessonNumber': 2,
              'marks': [
                {'id': 'mark-1', 'value': '6', 'mood': 'Average'}
              ],
            }
          ],
          'summativeMarks': [
            {
              'markId': 'sor-1',
              'sectionId': 'sec-1',
              'value': 9,
              'maxValue': 15,
              'type': 'СОР',
              'mood': 'Good',
            },
            {
              'markId': 'soch-1',
              'sectionId': 'sec-2',
              'value': 11,
              'maxValue': 20,
              'type': 'СОЧ',
              'mood': 'Average',
            },
          ],
          'finalWorks': [
            {
              'workId': 'agg-1',
              'periodNumber': 1,
              'type': 'Period',
              'periodId': '2395845913549013991',
              'marks': [
                {'id': 'agg-mark-1', 'value': '4', 'mood': 'Average'}
              ],
            }
          ],
          'lessonLogEntries': [
            {
              'id': 'att-1',
              'value': 'Н',
              'fullName': 'Пропуск',
              'date': '1763683200',
              'lessonId': 'lesson-1',
            }
          ],
        }
      ],
    };

    final parsed = parsePeriodAcademicPayload(
      payload,
      sourceEndpoint: 'period',
    );

    expect(parsed.results.where((it) => it.resultKind == 'regular').length, 1);
    expect(parsed.results.where((it) => it.resultKind == 'sor').length, 1);
    expect(parsed.results.where((it) => it.resultKind == 'soch').length, 1);
    expect(parsed.aggregates.where((it) => it.resultKind == 'term').length, 1);
    expect(parsed.attendance, hasLength(1));
    expect(parsed.attendance.first.providerSubjectId, 'sub-1');
    expect(parsed.attendance.first.subjectName, 'Math');
    expect(parsed.attendance.first.lessonNumber, 0);
    expect(parsed.attendance.first.providerLessonRef, 'lesson-1');
  });

  test('normalizeKundelikAttendanceCode maps raw code variants', () {
    expect(
      normalizeKundelikAttendanceCode(rawValue: 'н', fullName: ''),
      'absent',
    );
    expect(
      normalizeKundelikAttendanceCode(rawValue: 'Н', fullName: ''),
      'absent',
    );
    expect(
      normalizeKundelikAttendanceCode(rawValue: 'б', fullName: ''),
      'excused',
    );
    expect(
      normalizeKundelikAttendanceCode(rawValue: 'Б', fullName: ''),
      'excused',
    );
    expect(
      normalizeKundelikAttendanceCode(rawValue: 'п', fullName: ''),
      'excused',
    );
    expect(
      normalizeKundelikAttendanceCode(rawValue: 'П', fullName: ''),
      'excused',
    );
    expect(
      normalizeKundelikAttendanceCode(rawValue: 'о', fullName: ''),
      'late',
    );
    expect(
      normalizeKundelikAttendanceCode(rawValue: 'О', fullName: ''),
      'late',
    );
  });

  test('normalizeKundelikAttendanceCode maps fullName variants', () {
    expect(
      normalizeKundelikAttendanceCode(rawValue: '', fullName: 'Неявка'),
      'absent',
    );
    expect(
      normalizeKundelikAttendanceCode(
        rawValue: '',
        fullName: 'Пропуск без уваж. причины',
      ),
      'absent',
    );
    expect(
      normalizeKundelikAttendanceCode(rawValue: '', fullName: 'Болеет'),
      'excused',
    );
    expect(
      normalizeKundelikAttendanceCode(
        rawValue: '',
        fullName: 'Пропуск по болезни',
      ),
      'excused',
    );
    expect(
      normalizeKundelikAttendanceCode(
        rawValue: '',
        fullName: 'Пропуск по уваж. причине',
      ),
      'excused',
    );
    expect(
      normalizeKundelikAttendanceCode(rawValue: '', fullName: 'Опоздание'),
      'late',
    );
  });

  test('normalizeKundelikAttendanceCode returns null for unknown values', () {
    expect(
      normalizeKundelikAttendanceCode(rawValue: '', fullName: ''),
      isNull,
    );
    expect(
      normalizeKundelikAttendanceCode(rawValue: '???', fullName: '---'),
      isNull,
    );
  });

  test('parsePeriodAcademicPayload skips unknown attendance codes', () {
    final payload = {
      'periodId': '2395845913549013991',
      'subjects': [
        {
          'id': 'sub-1',
          'name': 'Math',
          'lessonLogEntries': [
            {'id': 'att-1', 'value': 'Н', 'date': '2026-03-30'},
            {'id': 'att-2', 'value': 'X', 'date': '2026-03-30'},
            {
              'id': 'att-3',
              'value': '',
              'fullName': 'Пропуск по болезни',
              'date': '2026-03-31',
            },
          ],
        }
      ],
    };

    final parsed =
        parsePeriodAcademicPayload(payload, sourceEndpoint: '/marks');
    expect(parsed.attendance, hasLength(2));
    expect(parsed.attendance[0].code, 'absent');
    expect(parsed.attendance[1].code, 'excused');
    expect(parsed.attendance.every((item) => item.code != 'unknown'), isTrue);
  });

  test('parseLessons prefers hours and preserves zero lesson number and place',
      () {
    final payload = {
      'days': [
        {
          'date': '1775740800',
          'lessons': [
            {
              'id': 'l-zero',
              'number': 0,
              'subjectName': 'Физика',
              'place': '312',
              'hours': {
                'startHour': '17',
                'startMinute': '30',
                'endHour': '18',
                'endMinute': '15',
              },
            }
          ],
        }
      ],
    };

    final lessons = parseLessons(payload);
    expect(lessons, hasLength(1));
    expect(lessons.first.lessonNumber, 0);
    expect(lessons.first.lessonPlace, '312');
    expect(lessons.first.startTime, '17:30');
    expect(lessons.first.endTime, '18:15');
  });
}
