import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/kundi_behavior/application/kundi_behavior_clock.dart';
import 'package:kundi_mobile/features/kundi_behavior/application/kundi_behavior_controller.dart';
import 'package:kundi_mobile/features/kundi_behavior/domain/kundi_behavior_event.dart';
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
import 'package:kundi_mobile/shared/theme/app_theme.dart';
import 'package:kundi_mobile/shared/widgets/student_pull_to_refresh.dart';

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

  testWidgets('light theme keeps Home title readable', (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    final theme = AppTheme.light;
    await tester.pumpWidget(
      _testApp(
        lessons: _sixLessons,
        summary: _summaryWithGrades,
        studentName: 'Артем',
        theme: theme,
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(
      find.byKey(const Key('home-header-title')),
    );
    expect(title.style?.color, theme.colorScheme.onSurface);
  });

  testWidgets('behavior flag false preserves the stable Home contract',
      (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    final clock = _FrozenBehaviorClock(DateTime.utc(2026, 4, 5, 7, 45));
    final behavior = KundiBehaviorController(clock: clock)
      ..dispatch(
        KundiBehaviorEvent(
          type: KundiBehaviorEventType.homeworkCompleted,
          id: 'modeled-celebration',
          occurredAt: clock.now(),
        ),
      );

    await tester.pumpWidget(
      _testApp(
        lessons: const <LessonsEntity>[],
        summary: SummaryEntity.empty,
        studentName: '',
        behaviorCoreEnabled: false,
        behaviorController: behavior,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Давай посмотрим, что запланировано на сегодня.'),
      findsOneWidget,
    );
    expect(find.text('Отличная работа!'), findsNothing);
    expect(find.byKey(KundiHomeHero.heroKey), findsOneWidget);
    expect(find.byKey(const Key('home-action-kundi')), findsOneWidget);
  });

  testWidgets('behavior flag true changes copy without changing Home geometry',
      (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    final clock = _FrozenBehaviorClock(DateTime.utc(2026, 4, 5, 7, 45));
    final behavior = KundiBehaviorController(clock: clock);

    await tester.pumpWidget(
      _testApp(
        lessons: _sixLessons,
        summary: _summaryWithGrades,
        studentName: 'Артем',
        behaviorCoreEnabled: true,
        behaviorController: behavior,
      ),
    );
    await tester.pumpAndSettle();

    final hero = find.byKey(KundiHomeHero.heroKey);
    final actions = find.byKey(const Key('home-action-rows'));
    final heroRectBefore = tester.getRect(hero);
    final actionsRectBefore = tester.getRect(actions);

    behavior.dispatch(
      KundiBehaviorEvent(
        type: KundiBehaviorEventType.homeworkCompleted,
        id: 'modeled-celebration',
        occurredAt: clock.now(),
      ),
    );
    await tester.pump();

    expect(find.text('Отличная работа!'), findsOneWidget);
    expect(tester.getRect(hero), heroRectBefore);
    expect(tester.getRect(actions), actionsRectBefore);
    final image = tester.widget<Image>(find.byKey(KundiHomeHero.assetKey));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/kundi/home/kundi_home.webp',
    );
    expect(tester.takeException(), isNull);
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

  testWidgets(
      'enabled Kundi row opens assistant callback without geometry change',
      (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    var assistantTapped = false;
    await tester.pumpWidget(
      _testApp(
        lessons: _sixLessons,
        summary: _summaryWithGrades,
        studentName: 'Артем',
        assistantEnabled: true,
        onAssistantTap: () => assistantTapped = true,
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(const Key('home-action-kundi'));
    expect(find.text('Скоро'), findsNothing);
    expect(find.text('Объяснит тему и поможет сделать первый шаг'),
        findsOneWidget);
    await tester.tap(action);
    await tester.pump();
    expect(assistantTapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar long press is distinct from tap on static fallback',
      (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    var taps = 0;
    var starts = 0;
    var ends = 0;
    var pointerDowns = 0;
    var pointerUps = 0;
    await tester.pumpWidget(
      _testApp(
        lessons: _sixLessons,
        summary: _summaryWithGrades,
        studentName: 'Артем',
        assistantEnabled: true,
        onAssistantTap: () => taps++,
        onAssistantPointerDown: (_) => pointerDowns++,
        onAssistantPointerUp: (_) => pointerUps++,
        onAssistantLongPressStart: (_) => starts++,
        onAssistantLongPressEnd: (_) => ends++,
      ),
    );
    await tester.pumpAndSettle();

    final avatar = find.byKey(const Key('kundi-home-avatar-gesture'));
    final gesture = await tester.startGesture(tester.getCenter(avatar));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(starts, 1);
    expect(ends, 1);
    expect(pointerDowns, 1);
    expect(pointerUps, 1);
    expect(taps, 0);
    expect(find.byKey(KundiHomeHero.heroKey), findsOneWidget);
  });

  testWidgets(
      'cancelled pointer then one long press are two pointer sequences but one accepted hold',
      (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    var taps = 0;
    var pointerDowns = 0;
    var pointerUps = 0;
    var pointerCancels = 0;
    var starts = 0;
    var ends = 0;
    await tester.pumpWidget(
      _testApp(
        lessons: _sixLessons,
        summary: _summaryWithGrades,
        studentName: 'Артем',
        assistantEnabled: true,
        onAssistantTap: () => taps++,
        onAssistantPointerDown: (_) => pointerDowns++,
        onAssistantPointerUp: (_) => pointerUps++,
        onAssistantPointerCancel: (_) => pointerCancels++,
        onAssistantLongPressStart: (_) => starts++,
        onAssistantLongPressEnd: (_) => ends++,
      ),
    );
    await tester.pumpAndSettle();

    final avatar = find.byKey(const Key('kundi-home-avatar-gesture'));
    final slipped = await tester.startGesture(tester.getCenter(avatar));
    await tester.pump(const Duration(milliseconds: 100));
    await slipped.cancel();
    await tester.pump();

    final accepted = await tester.startGesture(tester.getCenter(avatar));
    await tester.pump(const Duration(milliseconds: 600));
    await accepted.up();
    await tester.pump();

    expect(pointerDowns, 2);
    expect(pointerCancels, 1);
    expect(pointerUps, 1);
    expect(starts, 1);
    expect(ends, 1);
    expect(taps, 0);
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
    expect(find.text('Заданий на сегодня нет'), findsOneWidget);
    expect(find.text('Новых оценок нет'), findsOneWidget);
    expect(
      find.text('Давай посмотрим, что запланировано на сегодня.'),
      findsOneWidget,
    );
    _expectNoMojibake(tester);
  });

  testWidgets(
      'fitting Home has no empty scroll tail while pull refresh still runs',
      (tester) async {
    await _setSurface(tester, const Size(430, 1000));
    var refreshCalls = 0;
    await tester.pumpWidget(
      _testApp(
        lessons: const <LessonsEntity>[],
        summary: SummaryEntity.empty,
        studentName: '',
        refreshAction: () async {
          refreshCalls += 1;
        },
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('home-main-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, 0);

    await tester.drag(
        find.byKey(const Key('home-main-scroll')), const Offset(0, 320));
    await tester.pumpAndSettle();

    expect(refreshCalls, 1);
    expect(scrollable.position.pixels, 0);
  });

  testWidgets('narrow screen, long name and font scale 1.2 do not overflow',
      (tester) async {
    await _setSurface(tester, const Size(360, 800));
    final clock = _FrozenBehaviorClock(DateTime.utc(2026, 4, 5, 7, 45));
    final behavior = KundiBehaviorController(clock: clock)
      ..dispatch(
        KundiBehaviorEvent(
          type: KundiBehaviorEventType.assistantFailure,
          id: 'modeled-error',
          occurredAt: clock.now(),
        ),
      );
    await tester.pumpWidget(
      _testApp(
        lessons: _sixLessonsWithLongHomework,
        summary: _summaryWithGrades,
        studentName:
            'АлександрОченьДлинноеИмяДляПроверки ПереполненияИнтерфейса',
        textScale: 1.2,
        withBottomNavigation: true,
        behaviorCoreEnabled: true,
        behaviorController: behavior,
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
  VoidCallback? onAssistantTap,
  PointerDownEventListener? onAssistantPointerDown,
  PointerUpEventListener? onAssistantPointerUp,
  PointerCancelEventListener? onAssistantPointerCancel,
  GestureLongPressStartCallback? onAssistantLongPressStart,
  GestureLongPressEndCallback? onAssistantLongPressEnd,
  bool assistantEnabled = false,
  double textScale = 1,
  bool withBottomNavigation = false,
  bool behaviorCoreEnabled = false,
  KundiBehaviorController? behaviorController,
  Future<void> Function()? refreshAction,
  ThemeData? theme,
}) {
  final page = LessonsPage(
    now: DateTime(2026, 4, 5, 7, 45),
    onHomeworkTap: onHomeworkTap,
    onGradesTap: onGradesTap,
    onAssistantTap: onAssistantTap,
    onAssistantPointerDown: onAssistantPointerDown,
    onAssistantPointerUp: onAssistantPointerUp,
    onAssistantPointerCancel: onAssistantPointerCancel,
    onAssistantLongPressStart: onAssistantLongPressStart,
    onAssistantLongPressEnd: onAssistantLongPressEnd,
    assistantEnabled: assistantEnabled,
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
      kundiBehaviorCoreEnabledProvider.overrideWithValue(behaviorCoreEnabled),
      if (behaviorController != null)
        kundiBehaviorControllerProvider.overrideWith(
          (ref) => behaviorController,
        ),
      if (refreshAction != null)
        studentRefreshActionProvider.overrideWithValue(refreshAction),
    ],
    child: MaterialApp(
      theme: theme ?? ThemeData.dark(useMaterial3: true),
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

class _FrozenBehaviorClock implements KundiBehaviorClock {
  _FrozenBehaviorClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  @override
  KundiBehaviorTimerHandle schedule(
    DateTime deadline,
    void Function() callback,
  ) {
    return _FrozenTimerHandle();
  }

  @override
  void cancel(KundiBehaviorTimerHandle handle) {
    if (handle is _FrozenTimerHandle) {
      handle.canceled = true;
    }
  }
}

class _FrozenTimerHandle implements KundiBehaviorTimerHandle {
  bool canceled = false;
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
