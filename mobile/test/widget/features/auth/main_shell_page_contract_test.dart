import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/auth/presentation/main_shell_page.dart';
import 'package:kundi_mobile/features/grades/application/grades_controller.dart';
import 'package:kundi_mobile/features/grades/domain/grades_entity.dart';
import 'package:kundi_mobile/features/homework/application/homework_controller.dart';
import 'package:kundi_mobile/features/homework/domain/homework_entity.dart';
import 'package:kundi_mobile/features/lessons/application/lessons_controller.dart';
import 'package:kundi_mobile/features/lessons/domain/lessons_entity.dart';
import 'package:kundi_mobile/features/profile/application/profile_controller.dart';
import 'package:kundi_mobile/features/profile/domain/profile_entity.dart';
import 'package:kundi_mobile/features/summary/application/summary_controller.dart';
import 'package:kundi_mobile/features/summary/domain/summary_entity.dart';

void main() {
  testWidgets('root shell uses swipe-first 3-page contract', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
          homeworkControllerProvider.overrideWith(_FakeHomeworkController.new),
          gradesControllerProvider.overrideWith(_FakeGradesController.new),
          profileControllerProvider.overrideWith(_FakeProfileController.new),
          summaryControllerProvider.overrideWith(_FakeSummaryController.new),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Главная'), findsWidgets);

    await tester.drag(find.byType(PageView), const Offset(-450, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grades-tab-main')), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(450, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(450, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('homework-week-day-selector')), findsOneWidget);
  });

  testWidgets('homework mode/day state survives root swipe transitions',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsControllerProvider.overrideWith(_FakeLessonsController.new),
          homeworkControllerProvider.overrideWith(_FakeHomeworkController.new),
          gradesControllerProvider.overrideWith(_FakeGradesController.new),
          profileControllerProvider.overrideWith(_FakeProfileController.new),
          summaryControllerProvider.overrideWith(_FakeSummaryController.new),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(450, 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('Solve #12'), findsOneWidget);
    await tester.tap(find.text('Тема урока'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Квадратичные уравнения'), findsOneWidget);

    await tester.tap(find.byKey(const Key('homework-weekday-chip-6-off')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Электролиты и растворы'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-450, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-450, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(450, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(450, 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('Электролиты и растворы'), findsOneWidget);
    expect(find.textContaining('Solve #12'), findsNothing);
  });
}

class _FakeLessonsController extends LessonsController {
  @override
  Future<List<LessonsEntity>> build() async => _fakeLessons;

  @override
  Future<void> refreshFromCache() async {
    state = const AsyncData<List<LessonsEntity>>(_fakeLessons);
  }
}

class _FakeHomeworkController extends HomeworkController {
  @override
  Future<List<HomeworkEntity>> build() async => const <HomeworkEntity>[
        HomeworkEntity(
          id: 'hw-1',
          description: 'Read chapter',
          requiresPhoto: false,
          lessonDate: '2026-04-10',
          subjectName: 'Biology',
        ),
      ];

  @override
  Future<void> refreshFromCache() async {
    state = const AsyncData<List<HomeworkEntity>>(<HomeworkEntity>[
      HomeworkEntity(
        id: 'hw-1',
        description: 'Read chapter',
        requiresPhoto: false,
        lessonDate: '2026-04-10',
        subjectName: 'Biology',
      ),
    ]);
  }
}

class _FakeGradesController extends GradesController {
  @override
  Future<GradesScreenData> build() async => _fakeGradesData;

  @override
  Future<void> refreshFromCache() async {
    state = const AsyncData<GradesScreenData>(_fakeGradesData);
  }
}

class _FakeProfileController extends ProfileController {
  @override
  Future<ProfileEntity?> build() async => const ProfileEntity(
        readMode: 'v2',
        providerIdentity: ProviderIdentityProfileSection(
          studentId: 'student-1',
          provider: 'kundelik',
          providerAccountRef: 'acc-1',
          providerPersonId: 'person-1',
          providerSchoolId: 'school-1',
          providerGroupId: 'group-1',
          studentFullName: 'Artem Babanov',
          schoolName: 'Kundi School',
          classLabel: '7A',
          classTeacherFullName: 'Teacher',
          gradeLevel: 7,
        ),
        localAppProfile: null,
      );

  @override
  Future<void> refreshFromCache() async {
    state = await AsyncValue.guard(build);
  }
}

class _FakeSummaryController extends SummaryController {
  @override
  Future<SummaryEntity> build() async => SummaryEntity.empty;

  @override
  Future<void> refreshFromCache() async {
    state = const AsyncData<SummaryEntity>(SummaryEntity.empty);
  }
}

const _fakeLessons = <LessonsEntity>[
  LessonsEntity(
    id: 'lesson-1',
    date: '2026-04-10',
    lessonNumber: 1,
    startTime: '08:30',
    endTime: '09:15',
    subjectName: 'Algebra',
    topic: 'Квадратичные уравнения',
    homeworkText: 'Solve #12',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
  LessonsEntity(
    id: 'lesson-2',
    date: '2026-04-11',
    lessonNumber: 2,
    startTime: '09:20',
    endTime: '10:05',
    subjectName: 'Chemistry',
    topic: 'Электролиты и растворы',
    homeworkText: 'Параграф 18',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
];

const _fakeGradesData = GradesScreenData(
  readMode: 'v2',
  provider: 'kundelik',
  windowKey: 'wk',
  snapshotAt: '2026-04-10T00:00:00Z',
  availableWeeks: <GradesWeekOption>[],
  weeklyRowsByWeek: <String, List<WeeklySubjectGradesRow>>{},
  latestRegularResults: <LatestRegularResultItem>[
    LatestRegularResultItem(
      subjectKey: 'sub-1',
      subjectName: 'Algebra',
      value: '8',
      recordedOn: '2026-04-10',
      mood: 'good',
    ),
  ],
  summativeBySubject: <SubjectSummativeSection>[],
  aggregatesBySubject: <SubjectAggregateSection>[],
);
