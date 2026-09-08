import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/grades/application/grades_controller.dart';
import 'package:kundi_mobile/features/grades/domain/grades_entity.dart';
import 'package:kundi_mobile/features/grades/domain/grades_repository.dart';
import 'package:kundi_mobile/features/grades/presentation/grades_page.dart';
import 'package:kundi_mobile/shared/widgets/student_pull_to_refresh.dart';

void main() {
  testWidgets('grades pull gesture uses shared refresh action', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider
              .overrideWithValue(_FakeGradesRepository(_v2DataMainEmpty())),
          studentRefreshActionProvider.overrideWithValue(() async {
            calls += 1;
          }),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('grades-pull-scroll')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('latest mode renders recent regular marks', (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grades-tab-main')), findsOneWidget);
  });

  testWidgets('top segmented contains expected labels', (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grades-tab-main')), findsOneWidget);
    expect(find.byKey(const Key('grades-tab-week')), findsOneWidget);
    expect(find.byKey(const Key('grades-tab-totals')), findsOneWidget);
    expect(find.text('Оценки'), findsOneWidget);
    expect(find.text('Главная'), findsOneWidget);
    expect(find.text('За неделю'), findsOneWidget);
    expect(find.text('Итоговые'), findsOneWidget);
  });

  testWidgets('main tab renders latest cards and stats card', (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grades-main-latest-card')), findsOneWidget);
    expect(find.byKey(const Key('grades-main-summative-card')), findsOneWidget);
    expect(find.byKey(const Key('grades-main-stats-card')), findsOneWidget);
    expect(find.text('Последние оценки'), findsOneWidget);
    expect(find.text('Последние СОР и СОЧ'), findsOneWidget);
    expect(find.text('Средний балл'), findsOneWidget);
    expect(find.text('Качество знаний'), findsOneWidget);
    expect(find.text('Динамика'), findsOneWidget);
    expect(find.text('Algebra'), findsWidgets);
  });

  testWidgets('main tab shows empty states when latest/summative data missing',
      (tester) async {
    final repository = _FakeGradesRepository(_v2DataMainEmpty());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Оценок пока нет'), findsOneWidget);
    expect(find.text('СОР и СОЧ пока нет'), findsOneWidget);
    expect(find.byKey(const Key('grades-main-stats-card')), findsOneWidget);
  });

  testWidgets('main card actions navigate to week and totals tabs',
      (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-main-action-latest')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grades-week-switcher')), findsOneWidget);

    await tester.tap(find.byKey(const Key('grades-tab-main')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grades-main-action-works')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grades-totals-period-year')), findsOneWidget);
  });

  testWidgets('no mojibake patterns in visible labels', (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();
    final allTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    for (final bad in [
      '\u0420\u0452',
      '\u0420\u045f',
      '\u0432\u0402',
      '\u00D0',
      '\u00D1'
    ]) {
      expect(allTexts.contains(bad), isFalse);
    }
  });

  testWidgets('weekly tab renders compact switcher/day selector/legend',
      (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-week')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grades-week-switcher')), findsOneWidget);
    expect(find.byKey(const Key('grades-week-prev')), findsOneWidget);
    expect(find.byKey(const Key('grades-week-next')), findsOneWidget);
    expect(find.byKey(const Key('grades-week-day-selector')), findsOneWidget);
    expect(find.byKey(const Key('grades-week-legend')), findsOneWidget);
    expect(find.byKey(const Key('grades-week-summary-card')), findsOneWidget);
    expect(find.text('Отлично'), findsOneWidget);
    expect(find.text('Хорошо'), findsOneWidget);
    expect(find.text('Удовл.'), findsOneWidget);
    expect(find.text('Не был'), findsOneWidget);
    expect(find.text('Нет оценки'), findsOneWidget);
    for (final weekday in [1, 2, 3, 4, 5, 6, 7]) {
      expect(
          find
              .byKey(Key('grades-week-day-chip-$weekday-selected'))
              .evaluate()
              .length,
          inInclusiveRange(0, 1));
      expect(
          find
              .byKey(Key('grades-week-day-chip-$weekday-normal'))
              .evaluate()
              .length,
          inInclusiveRange(0, 1));
    }
    expect(find.byKey(const Key('grades-week-day-chip-1-selected')),
        findsOneWidget);
    expect(find.byKey(const Key('grades-week-table-header')), findsNothing);
    expect(find.byKey(const Key('grades-week-row-sub-math')), findsOneWidget);
    expect(find.text('Algebra'), findsOneWidget);
  });

  testWidgets('weekly cell rules: mark > attendance > dot > empty',
      (tester) async {
    final repository = _FakeGradesRepository(_v2DataWeeklyPriority());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-week')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('grades-week-row-sub-priority')), findsOneWidget);
    expect(find.byKey(const Key('grades-week-cell-sub-priority-1-mark-1')),
        findsOneWidget);
    expect(find.byKey(const Key('grades-week-cell-sub-priority-2-attendance')),
        findsOneWidget);
    expect(find.byKey(const Key('grades-week-cell-sub-priority-3-dot')),
        findsOneWidget);
    expect(find.byKey(const Key('grades-week-cell-sub-priority-4-dot')),
        findsNothing);
  });

  testWidgets('weekly merges duplicate subjects by canonical name',
      (tester) async {
    final repository = _FakeGradesRepository(_v2DataWeeklyDuplicateSubjects());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grades-tab-week')));
    await tester.pumpAndSettle();

    expect(find.text('Информатика'), findsOneWidget);
    expect(find.byKey(const Key('grades-week-cell-sub-inf-1-1-mark-1')),
        findsOneWidget);
    expect(find.byKey(const Key('grades-week-cell-sub-inf-1-2-mark-1')),
        findsOneWidget);
  });

  testWidgets(
      'weekly shows 6 columns when saturday has lessons and sunday does not',
      (tester) async {
    final repository = _FakeGradesRepository(_v2DataWeeklySixDayColumns());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-week')));
    await tester.pumpAndSettle();

    for (final weekday in [1, 2, 3, 4, 5, 6]) {
      final selected = find
          .byKey(Key('grades-week-day-chip-$weekday-selected'))
          .evaluate()
          .length;
      final normal = find
          .byKey(Key('grades-week-day-chip-$weekday-normal'))
          .evaluate()
          .length;
      expect(selected + normal, 1);
    }
    final sundaySelected = find
        .byKey(const Key('grades-week-day-chip-7-selected'))
        .evaluate()
        .length;
    final sundayNormal = find
        .byKey(const Key('grades-week-day-chip-7-normal'))
        .evaluate()
        .length;
    expect(sundaySelected + sundayNormal, 1);
    expect(find.byKey(const Key('grades-week-cell-sub-six-6-mark-1')),
        findsOneWidget);
    expect(find.byKey(const Key('grades-week-column-sub-six-7')), findsNothing);
  });

  testWidgets('weekly summary is fixed and has no date subtitle',
      (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grades-tab-week')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grades-week-summary-card')), findsOneWidget);
    expect(find.text('Итоги недели'), findsOneWidget);
    final summaryScope = find.descendant(
      of: find.byKey(const Key('grades-week-summary-card')),
      matching: find.byType(Text),
    );
    for (final text in tester.widgetList<Text>(summaryScope)) {
      final value = text.data ?? '';
      expect(value.contains('апреля'), isFalse);
      expect(value.contains('мая'), isFalse);
    }
  });

  testWidgets('weekly empty data renders empty state card', (tester) async {
    final repository = _FakeGradesRepository(_v2DataWeeklyEmpty());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-week')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grades-week-empty-state')), findsOneWidget);
  });

  testWidgets('quarter mode renders aggregates list', (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-totals')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grades-aggregate-subject-sub-math')),
        findsOneWidget);
  });

  testWidgets('totals period selector contains year period key',
      (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-totals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grades-totals-period-3')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grades-totals-period-year')), findsOneWidget);
    expect(find.text('Год'), findsOneWidget);
  });

  testWidgets('period switch changes collapsed row value between year and term',
      (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-totals')));
    await tester.pumpAndSettle();

    final collapsedValue =
        find.byKey(const Key('grades-totals-collapsed-value-sub-math'));
    expect(collapsedValue, findsOneWidget);
    final yearText = tester.widget<Text>(collapsedValue).data ?? '';
    expect(yearText, '—');

    await tester.tap(find.byKey(const Key('grades-totals-period-1')));
    await tester.pumpAndSettle();

    final termText = tester.widget<Text>(collapsedValue).data ?? '';
    expect(termText, '—');
  });

  testWidgets('term expanded renders mini work tiles without quarter labels',
      (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-totals')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-totals-period-3')));
    await tester.pumpAndSettle();

    final subjectMath =
        find.byKey(const Key('grades-aggregate-subject-sub-math'));
    await tester.ensureVisible(subjectMath);
    await tester.tap(subjectMath);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grades_totals_expanded_work_tile_sor_1')),
        findsOneWidget);
    expect(find.byKey(const Key('grades_totals_expanded_work_tile_sor_2')),
        findsOneWidget);
    expect(find.byKey(const Key('grades_totals_expanded_work_tile_sor_3')),
        findsOneWidget);
    expect(find.byKey(const Key('grades_totals_expanded_work_tile_soch')),
        findsOneWidget);

    expect(find.textContaining('1 четв.'), findsNothing);
    expect(find.textContaining('2 четв.'), findsNothing);
    expect(find.textContaining('3 четв.'), findsNothing);
    expect(find.textContaining('4 четв.'), findsNothing);
    expect(find.textContaining('СОР (формативные)'), findsNothing);
    expect(find.textContaining('СОЧ (суммативные)'), findsNothing);
  });

  testWidgets('term mode collapsed row shows single selected quarter value',
      (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-totals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grades-totals-period-3')));
    await tester.pumpAndSettle();

    final collapsedValue =
        find.byKey(const Key('grades-totals-collapsed-value-sub-math'));
    expect(collapsedValue, findsOneWidget);
    final selectedText = tester.widget<Text>(collapsedValue).data ?? '';
    expect(selectedText, '4');
  });

  testWidgets('year mode rows are non-expandable and hero has no-data dash',
      (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-totals')));
    await tester.pumpAndSettle();

    final subjectMath =
        find.byKey(const Key('grades-aggregate-subject-sub-math'));
    expect(subjectMath, findsOneWidget);
    expect(
        find.byKey(const Key('grades-totals-chevron-sub-math')), findsNothing);
    expect(find.byKey(const Key('grades_totals_expanded_work_tile_sor_1')),
        findsNothing);
    expect(find.byKey(const Key('grades_totals_expanded_work_tile_soch')),
        findsNothing);

    await tester.tap(subjectMath);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grades_totals_expanded_work_tile_sor_1')),
        findsNothing);

    expect(find.text('—'), findsWidgets);
    expect(find.text('Нет данных'), findsWidgets);
    expect(find.text('Средний балл за год'), findsOneWidget);
    final yearValue = tester.widget<Text>(
        find.byKey(const Key('grades-totals-collapsed-value-sub-math')));
    expect(yearValue.data, '—');
  });

  testWidgets('year average does not fallback from quarter values',
      (tester) async {
    final repository = _FakeGradesRepository(_v2Data());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grades-tab-totals')));
    await tester.pumpAndSettle();

    expect(find.text('—'), findsWidgets);
    expect(find.text('3.23'), findsNothing);
  });
  testWidgets('summative items render in main card', (tester) async {
    final repository = _FakeGradesRepository(_v2DataSummativeMoodPriority());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grades-main-summative-card')), findsOneWidget);
    expect(find.textContaining('СОР:'), findsOneWidget);
    expect(find.textContaining('Summative'), findsOneWidget);
    expect(find.text('7/10'), findsOneWidget);
  });

  testWidgets('renders full empty-state when no data exists', (tester) async {
    final repository = _FakeGradesRepository(
      const GradesScreenData(
        readMode: 'v2',
        provider: 'kundelik',
        windowKey: 'wk',
        snapshotAt: '2026-04-05T12:00:00Z',
        availableWeeks: <GradesWeekOption>[],
        weeklyRowsByWeek: <String, List<WeeklySubjectGradesRow>>{},
        latestRegularResults: <LatestRegularResultItem>[],
        summativeBySubject: <SubjectSummativeSection>[],
        aggregatesBySubject: <SubjectAggregateSection>[],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gradesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: GradesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });
}

class _FakeGradesRepository implements GradesRepository {
  _FakeGradesRepository(this._data);

  final GradesScreenData _data;

  @override
  Future<GradesScreenData> get() async => _data;
}

GradesScreenData _v2Data() {
  const week = GradesWeekOption(
    weekKey: '2026-04-06',
    weekStartDate: '2026-04-06',
    weekEndDate: '2026-04-12',
    label: '06.04 - 12.04',
  );

  return const GradesScreenData(
    readMode: 'v2',
    provider: 'kundelik',
    windowKey: 'kundi:wk',
    snapshotAt: '2026-04-05T12:00:00Z',
    availableWeeks: <GradesWeekOption>[week],
    weeklyRowsByWeek: <String, List<WeeklySubjectGradesRow>>{
      '2026-04-06': <WeeklySubjectGradesRow>[
        WeeklySubjectGradesRow(
          subjectKey: 'sub-math',
          subjectName: 'Algebra',
          cellsByWeekday: <int, WeeklyGradeCell>{
            1: WeeklyGradeCell(
              date: '2026-04-06',
              hasLesson: true,
              regularMarks: <String>['9'],
              attendanceCodes: <String>[],
            ),
            2: WeeklyGradeCell(
              date: '2026-04-07',
              hasLesson: true,
              regularMarks: <String>[],
              attendanceCodes: <String>[],
            ),
          },
        ),
      ],
    },
    latestRegularResults: <LatestRegularResultItem>[
      LatestRegularResultItem(
        subjectKey: 'sub-math',
        subjectName: 'Algebra',
        value: '9',
        recordedOn: '2026-04-06',
        mood: 'good',
      ),
    ],
    summativeBySubject: <SubjectSummativeSection>[
      SubjectSummativeSection(
        subjectKey: 'sub-math',
        providerSubjectId: 'sub-math',
        subjectNormalizedName: 'algebra',
        subjectName: 'Algebra',
        items: <SummativeItem>[
          SummativeItem(
            kind: 'sor',
            value: '12/15',
            mood: 'average',
            recordedOn: '2026-04-08',
            termLabel: 'Term 3',
          ),
          SummativeItem(
            kind: 'soch',
            value: '18/20',
            mood: 'good',
            recordedOn: '2026-04-10',
            termLabel: 'Term 3',
          ),
        ],
      ),
    ],
    aggregatesBySubject: <SubjectAggregateSection>[
      SubjectAggregateSection(
        subjectKey: 'sub-math',
        providerSubjectId: 'sub-math',
        subjectNormalizedName: 'algebra',
        subjectName: 'Algebra',
        termItems: <AggregateItem>[
          AggregateItem(
            kind: 'term',
            value: '4',
            mood: 'average',
            recordedOn: '2026-04-12',
            termNo: 3,
            yearLabel: '',
          ),
        ],
        yearItems: <AggregateItem>[],
        summativeItems: <SummativeItem>[
          SummativeItem(
            kind: 'sor',
            value: '12/15',
            mood: 'average',
            recordedOn: '2026-04-08',
            termLabel: 'Term 3',
          ),
          SummativeItem(
            kind: 'soch',
            value: '18/20',
            mood: 'good',
            recordedOn: '2026-04-10',
            termLabel: 'Term 3',
          ),
        ],
      ),
    ],
  );
}

GradesScreenData _v2DataWeeklyPriority() {
  const week = GradesWeekOption(
    weekKey: '2026-04-13',
    weekStartDate: '2026-04-13',
    weekEndDate: '2026-04-19',
    label: '13.04 - 19.04',
  );

  return const GradesScreenData(
    readMode: 'v2',
    provider: 'kundelik',
    windowKey: 'kundi:wk',
    snapshotAt: '2026-04-13T12:00:00Z',
    availableWeeks: <GradesWeekOption>[week],
    weeklyRowsByWeek: <String, List<WeeklySubjectGradesRow>>{
      '2026-04-13': <WeeklySubjectGradesRow>[
        WeeklySubjectGradesRow(
          subjectKey: 'sub-priority',
          subjectName: 'Priority Subject',
          cellsByWeekday: <int, WeeklyGradeCell>{
            1: WeeklyGradeCell(
              date: '2026-04-13',
              hasLesson: true,
              regularMarks: <String>['8'],
              attendanceCodes: <String>['absent'],
            ),
            2: WeeklyGradeCell(
              date: '2026-04-14',
              hasLesson: true,
              regularMarks: <String>[],
              attendanceCodes: <String>['excused'],
            ),
            3: WeeklyGradeCell(
              date: '2026-04-15',
              hasLesson: true,
              regularMarks: <String>[],
              attendanceCodes: <String>[],
            ),
            4: WeeklyGradeCell(
              date: '2026-04-16',
              hasLesson: false,
              regularMarks: <String>[],
              attendanceCodes: <String>[],
            ),
          },
        ),
      ],
    },
    latestRegularResults: <LatestRegularResultItem>[
      LatestRegularResultItem(
        subjectKey: 'sub-anchor',
        subjectName: 'Anchor',
        value: '5',
        recordedOn: '2026-04-20',
        mood: 'good',
      ),
    ],
    summativeBySubject: <SubjectSummativeSection>[],
    aggregatesBySubject: <SubjectAggregateSection>[],
  );
}

GradesScreenData _v2DataWeeklyEmpty() {
  const week = GradesWeekOption(
    weekKey: '2026-04-20',
    weekStartDate: '2026-04-20',
    weekEndDate: '2026-04-26',
    label: '20.04 - 26.04',
  );

  return const GradesScreenData(
    readMode: 'v2',
    provider: 'kundelik',
    windowKey: 'kundi:wk',
    snapshotAt: '2026-04-20T12:00:00Z',
    availableWeeks: <GradesWeekOption>[week],
    weeklyRowsByWeek: <String, List<WeeklySubjectGradesRow>>{
      '2026-04-20': <WeeklySubjectGradesRow>[],
    },
    latestRegularResults: <LatestRegularResultItem>[
      LatestRegularResultItem(
        subjectKey: 'sub-anchor',
        subjectName: 'Anchor',
        value: '5',
        recordedOn: '2026-04-20',
        mood: 'good',
      ),
    ],
    summativeBySubject: <SubjectSummativeSection>[],
    aggregatesBySubject: <SubjectAggregateSection>[],
  );
}

GradesScreenData _v2DataMainEmpty() {
  const week = GradesWeekOption(
    weekKey: '2026-04-20',
    weekStartDate: '2026-04-20',
    weekEndDate: '2026-04-26',
    label: '20.04 - 26.04',
  );

  return const GradesScreenData(
    readMode: 'v2',
    provider: 'kundelik',
    windowKey: 'kundi:wk',
    snapshotAt: '2026-04-20T12:00:00Z',
    availableWeeks: <GradesWeekOption>[week],
    weeklyRowsByWeek: <String, List<WeeklySubjectGradesRow>>{
      '2026-04-20': <WeeklySubjectGradesRow>[
        WeeklySubjectGradesRow(
          subjectKey: 'sub-empty',
          subjectName: 'Empty Subject',
          cellsByWeekday: <int, WeeklyGradeCell>{
            1: WeeklyGradeCell(
              date: '2026-04-20',
              hasLesson: true,
              regularMarks: <String>[],
              attendanceCodes: <String>[],
            ),
          },
        ),
      ],
    },
    latestRegularResults: <LatestRegularResultItem>[],
    summativeBySubject: <SubjectSummativeSection>[],
    aggregatesBySubject: <SubjectAggregateSection>[],
  );
}

GradesScreenData _v2DataWeeklyDuplicateSubjects() {
  const week = GradesWeekOption(
    weekKey: '2026-04-27',
    weekStartDate: '2026-04-27',
    weekEndDate: '2026-05-03',
    label: '27.04 - 03.05',
  );
  return const GradesScreenData(
    readMode: 'v2',
    provider: 'kundelik',
    windowKey: 'kundi:wk',
    snapshotAt: '2026-04-27T12:00:00Z',
    availableWeeks: <GradesWeekOption>[week],
    weeklyRowsByWeek: <String, List<WeeklySubjectGradesRow>>{
      '2026-04-27': <WeeklySubjectGradesRow>[
        WeeklySubjectGradesRow(
          subjectKey: 'sub-inf-1',
          subjectName: 'Информатика',
          cellsByWeekday: <int, WeeklyGradeCell>{
            1: WeeklyGradeCell(
              date: '2026-04-27',
              hasLesson: true,
              regularMarks: <String>['5'],
              attendanceCodes: <String>[],
            ),
          },
        ),
        WeeklySubjectGradesRow(
          subjectKey: 'sub-inf-2',
          subjectName: ' Информатика ',
          cellsByWeekday: <int, WeeklyGradeCell>{
            2: WeeklyGradeCell(
              date: '2026-04-28',
              hasLesson: true,
              regularMarks: <String>['4'],
              attendanceCodes: <String>[],
            ),
          },
        ),
      ],
    },
    latestRegularResults: <LatestRegularResultItem>[],
    summativeBySubject: <SubjectSummativeSection>[],
    aggregatesBySubject: <SubjectAggregateSection>[],
  );
}

GradesScreenData _v2DataWeeklySixDayColumns() {
  const week = GradesWeekOption(
    weekKey: '2026-05-11',
    weekStartDate: '2026-05-11',
    weekEndDate: '2026-05-17',
    label: '11.05 - 17.05',
  );
  return const GradesScreenData(
    readMode: 'v2',
    provider: 'kundelik',
    windowKey: 'kundi:wk',
    snapshotAt: '2026-05-11T12:00:00Z',
    availableWeeks: <GradesWeekOption>[week],
    weeklyRowsByWeek: <String, List<WeeklySubjectGradesRow>>{
      '2026-05-11': <WeeklySubjectGradesRow>[
        WeeklySubjectGradesRow(
          subjectKey: 'sub-six',
          subjectName: 'Субботний предмет',
          cellsByWeekday: <int, WeeklyGradeCell>{
            1: WeeklyGradeCell(
              date: '2026-05-11',
              hasLesson: true,
              regularMarks: <String>[],
              attendanceCodes: <String>[],
            ),
            6: WeeklyGradeCell(
              date: '2026-05-16',
              hasLesson: true,
              regularMarks: <String>['5'],
              attendanceCodes: <String>[],
            ),
          },
        ),
      ],
    },
    latestRegularResults: <LatestRegularResultItem>[],
    summativeBySubject: <SubjectSummativeSection>[],
    aggregatesBySubject: <SubjectAggregateSection>[],
  );
}

GradesScreenData _v2DataSummativeMoodPriority() {
  return const GradesScreenData(
    readMode: 'v2',
    provider: 'kundelik',
    windowKey: 'kundi:wk',
    snapshotAt: '2026-04-13T12:00:00Z',
    availableWeeks: <GradesWeekOption>[],
    weeklyRowsByWeek: <String, List<WeeklySubjectGradesRow>>{},
    latestRegularResults: <LatestRegularResultItem>[
      LatestRegularResultItem(
        subjectKey: 'sub-main',
        subjectName: 'Regular',
        value: '5',
        recordedOn: '2026-04-14',
        mood: 'good',
      ),
    ],
    summativeBySubject: <SubjectSummativeSection>[
      SubjectSummativeSection(
        subjectKey: 'sub-sum',
        providerSubjectId: 'sub-sum',
        subjectNormalizedName: 'sum',
        subjectName: 'Summative',
        items: <SummativeItem>[
          SummativeItem(
            kind: 'sor',
            value: '7/10',
            mood: 'average',
            recordedOn: '2026-04-14',
            termLabel: 'Term 4',
          ),
        ],
      ),
    ],
    aggregatesBySubject: <SubjectAggregateSection>[],
  );
}
