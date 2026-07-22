import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/lessons/application/lessons_controller.dart';
import 'package:kundi_mobile/features/lessons/domain/lessons_entity.dart';
import 'package:kundi_mobile/features/lessons/domain/lessons_repository.dart';
import 'package:kundi_mobile/features/lessons/presentation/lessons_page.dart';
import 'package:kundi_mobile/features/lessons/presentation/widgets/kundi_home_hero.dart';
import 'package:kundi_mobile/features/profile/application/profile_controller.dart';
import 'package:kundi_mobile/features/profile/domain/profile_entity.dart';
import 'package:kundi_mobile/features/summary/application/summary_controller.dart';
import 'package:kundi_mobile/features/summary/domain/summary_entity.dart';
import 'package:kundi_mobile/features/summary/domain/summary_repository.dart';

void main() {
  testWidgets('home header, gamification panel and hero use current data',
      (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(
      _testApp(
        lessons: _sixLessons,
        summary: _summaryWithGrades,
        studentName: 'Бабанов Артем',
      ),
    );
    await tester.pumpAndSettle();

    final summaryFinder = find.byKey(const Key('home-summary-panel'));
    final heroFinder = find.byKey(KundiHomeHero.heroKey);
    expect(find.byKey(const Key('home-header-title')), findsOneWidget);
    expect(find.text('Главная'), findsOneWidget);
    expect(find.byKey(const Key('home-greeting')), findsNothing);
    expect(find.text('Доброе утро, Артем'), findsOneWidget);
    expect(find.text('Воскресенье, 5 апреля'), findsOneWidget);
    expect(summaryFinder, findsOneWidget);
    expect(tester.getTopLeft(summaryFinder).dy,
        lessThan(tester.getTopLeft(heroFinder).dy));
    expect(
      find.descendant(
        of: summaryFinder,
        matching: find.text('ДЗ сегодня'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summaryFinder,
        matching: find.text('ДЗ за неделю'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summaryFinder,
        matching: find.text('Посещаемость'),
      ),
      findsOneWidget,
    );
    expect(find.text('8 • 7'), findsOneWidget);
    expect(heroFinder, findsOneWidget);
    expect(find.byKey(KundiHomeHero.assetKey), findsOneWidget);
    final image = tester.widget<Image>(find.byKey(KundiHomeHero.assetKey));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/kundi/home/kundi_home.webp',
    );
    expect(find.byKey(const Key('home-action-homework')), findsOneWidget);
    expect(find.byKey(const Key('home-action-grades')), findsOneWidget);
    expect(find.byKey(const Key('home-action-kundi')), findsOneWidget);
    _expectNoMojibake(tester);
  });

  testWidgets('homework and grades rows use existing callbacks',
      (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    var homeworkTapped = false;
    var gradesTapped = false;
    await tester.pumpWidget(
      _testApp(
        lessons: _sixLessons,
        summary: _summaryWithGrades,
        studentName: 'Артем',
        onHomeworkTap: () => homeworkTapped = true,
        onGradesTap: () => gradesTapped = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-quick-action-homework')));
    await tester.tap(find.byKey(const Key('home-quick-action-grades')));
    await tester.pump();

    expect(homeworkTapped, isTrue);
    expect(gradesTapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kundi placeholder is disabled and has no navigation chevron',
      (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(
      _testApp(
        lessons: const <LessonsEntity>[],
        summary: SummaryEntity.empty,
        studentName: '',
      ),
    );
    await tester.pumpAndSettle();

    final placeholder = find.byKey(const Key('home-action-kundi'));
    expect(find.text('Спросите Kundi...'), findsOneWidget);
    expect(find.text('Скоро'), findsOneWidget);
    expect(
      find.descendant(
        of: placeholder,
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsNothing,
    );
    await tester.tap(placeholder);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses results title when recent values are summative',
      (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(
      _testApp(
        lessons: _sixLessons,
        summary: _summaryWithSummativeResults,
        studentName: 'Бабанов Артем',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Последние результаты'), findsOneWidget);
    expect(find.text('14/25 • 16/30 • 8/20'), findsOneWidget);
  });

  testWidgets('empty day uses explicit real-data fallbacks', (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(
      _testApp(
        lessons: const <LessonsEntity>[],
        summary: SummaryEntity.empty,
        studentName: '',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-summary-panel')), findsOneWidget);
    expect(find.text('Нет уроков'), findsOneWidget);
    expect(find.text('Заданий на сегодня нет'), findsOneWidget);
    expect(find.text('Новых оценок нет'), findsOneWidget);
    expect(
      find.text('Давай посмотрим, что запланировано на сегодня.'),
      findsOneWidget,
    );
    _expectNoMojibake(tester);
  });

  testWidgets('narrow screen, long name and font scale 1.2 do not overflow',
      (tester) async {
    await _setSurface(tester, const Size(360, 800));
    await tester.pumpWidget(
      _testApp(
        lessons: _sixLessonsWithLongHomework,
        summary: _summaryWithGrades,
        studentName:
            'АлександрОченьДлинноеИмяДляПроверки ПереполненияИнтерфейса',
        textScale: 1.2,
        withBottomNavigation: true,
      ),
    );
    await tester.pumpAndSettle();
    final placeholder = find.byKey(const Key('home-action-kundi'));
    await tester.ensureVisible(placeholder);
    await tester.pumpAndSettle();

    expect(find.byKey(KundiHomeHero.heroKey), findsOneWidget);
    expect(placeholder, findsOneWidget);
    expect(
      tester.getBottomLeft(placeholder).dy,
      lessThanOrEqualTo(734),
    );
    expect(tester.takeException(), isNull);
    _expectNoMojibake(tester);
  });
}

Widget _testApp({
  required List<LessonsEntity> lessons,
  required SummaryEntity summary,
  required String studentName,
  VoidCallback? onHomeworkTap,
  VoidCallback? onGradesTap,
  double textScale = 1,
  bool withBottomNavigation = false,
}) {
  final page = LessonsPage(
    now: DateTime(2026, 4, 5, 7, 45),
    onHomeworkTap: onHomeworkTap,
    onGradesTap: onGradesTap,
  );
  final home = withBottomNavigation
      ? Scaffold(
          bottomNavigationBar: const SizedBox(height: 66),
          body: page,
        )
      : page;

  return ProviderScope(
    overrides: [
      lessonsRepositoryProvider
          .overrideWithValue(_FakeLessonsRepository(lessons)),
      summaryRepositoryProvider
          .overrideWithValue(_FakeSummaryRepository(summary)),
      profileControllerProvider.overrideWith(
        () => _FakeProfileController(studentName),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: home,
    ),
  );
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

void _expectNoMojibake(WidgetTester tester) {
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? '')
      .join('\n');
  expect(visibleText, isNot(contains(RegExp(r'Рµ|Р°|СЃ|вЂ'))));
}

class _FakeLessonsRepository implements LessonsRepository {
  _FakeLessonsRepository(this._items);

  final List<LessonsEntity> _items;

  @override
  Future<List<LessonsEntity>> list() async => _items;
}

class _FakeSummaryRepository implements SummaryRepository {
  _FakeSummaryRepository(this._entity);

  final SummaryEntity _entity;

  @override
  Future<SummaryEntity> get() async => _entity;
}

class _FakeProfileController extends ProfileController {
  _FakeProfileController(this.studentName);

  final String studentName;

  @override
  Future<ProfileEntity?> build() async => ProfileEntity(
        readMode: 'v2',
        providerIdentity: ProviderIdentityProfileSection(
          studentId: 'student-1',
          provider: 'kundelik',
          providerAccountRef: 'account-1',
          providerPersonId: 'person-1',
          providerSchoolId: 'school-1',
          providerGroupId: 'group-1',
          studentFullName: studentName,
          schoolName: 'Школа',
          classLabel: '7А',
          classTeacherFullName: 'Учитель',
          gradeLevel: 7,
        ),
        localAppProfile: null,
      );
}

const _summaryWithGrades = SummaryEntity(
  available: true,
  lessonsCount: 6,
  homeworkCount: 3,
  resultsCount: 2,
  attendanceCount: 0,
  aggregatesCount: 0,
  recentResults: <SummaryResultHighlightEntity>[
    SummaryResultHighlightEntity(
      resultId: 'result-1',
      resultKind: 'regular',
      subjectName: 'Алгебра',
      valueText: '8',
      recordedOn: '2026-04-05',
      resolvedMood: 'good',
    ),
    SummaryResultHighlightEntity(
      resultId: 'result-2',
      resultKind: 'regular',
      subjectName: 'История',
      valueText: '7',
      recordedOn: '2026-04-04',
      resolvedMood: 'good',
    ),
  ],
  upcomingLessons: <SummaryLessonHighlightEntity>[],
);

const _summaryWithSummativeResults = SummaryEntity(
  available: true,
  lessonsCount: 0,
  homeworkCount: 0,
  resultsCount: 3,
  attendanceCount: 0,
  aggregatesCount: 0,
  recentResults: <SummaryResultHighlightEntity>[
    SummaryResultHighlightEntity(
      resultId: 'sor-1',
      resultKind: 'sor',
      subjectName: 'Физика',
      valueText: '14/25',
      recordedOn: '2026-04-05',
      resolvedMood: 'good',
    ),
    SummaryResultHighlightEntity(
      resultId: 'soch-1',
      resultKind: 'soch',
      subjectName: 'История',
      valueText: '16/30',
      recordedOn: '2026-04-04',
      resolvedMood: 'good',
    ),
    SummaryResultHighlightEntity(
      resultId: 'sor-2',
      resultKind: 'sor',
      subjectName: 'Алгебра',
      valueText: '8/20',
      recordedOn: '2026-04-03',
      resolvedMood: 'good',
    ),
  ],
  upcomingLessons: <SummaryLessonHighlightEntity>[],
);

const _sixLessons = <LessonsEntity>[
  LessonsEntity(
    id: 'lesson-1',
    date: '2026-04-05',
    lessonNumber: 1,
    startTime: '08:30',
    endTime: '09:15',
    subjectName: 'Алгебра',
    topic: 'Уравнения',
    homeworkText: 'Упражнение 12',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
  LessonsEntity(
    id: 'lesson-2',
    date: '2026-04-05',
    lessonNumber: 2,
    startTime: '09:25',
    endTime: '10:10',
    subjectName: 'Биология',
    topic: 'Клетка',
    homeworkText: 'Параграф 8',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
  LessonsEntity(
    id: 'lesson-3',
    date: '2026-04-05',
    lessonNumber: 3,
    startTime: '10:20',
    endTime: '11:05',
    subjectName: 'История',
    topic: 'Средние века',
    homeworkText: 'Прочитать главу',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
  LessonsEntity(
    id: 'lesson-4',
    date: '2026-04-05',
    lessonNumber: 4,
    startTime: '11:15',
    endTime: '12:00',
    subjectName: 'Физика',
    topic: 'Сила',
    homeworkText: '',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
  LessonsEntity(
    id: 'lesson-5',
    date: '2026-04-05',
    lessonNumber: 5,
    startTime: '12:10',
    endTime: '12:55',
    subjectName: 'Литература',
    topic: 'Поэзия',
    homeworkText: '',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
  LessonsEntity(
    id: 'lesson-6',
    date: '2026-04-05',
    lessonNumber: 6,
    startTime: '13:05',
    endTime: '13:50',
    subjectName: 'Информатика',
    topic: 'Алгоритмы',
    homeworkText: '',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
];

const _sixLessonsWithLongHomework = <LessonsEntity>[
  LessonsEntity(
    id: 'lesson-long-1',
    date: '2026-04-05',
    lessonNumber: 1,
    startTime: '08:30',
    endTime: '09:15',
    subjectName: 'Очень длинное название учебного предмета',
    topic: 'Большая тема',
    homeworkText:
        'Очень большое домашнее задание с подробным описанием, номерами страниц и дополнительными условиями выполнения',
    requiresPhoto: false,
    gradeValue: '',
    attendanceCode: '',
  ),
  ..._sixLessons,
];
