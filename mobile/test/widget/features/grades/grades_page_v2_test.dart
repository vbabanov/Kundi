import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/grades/application/grades_controller.dart';
import 'package:kundi_mobile/features/grades/domain/grades_entity.dart';
import 'package:kundi_mobile/features/grades/domain/grades_repository.dart';
import 'package:kundi_mobile/features/grades/presentation/grades_page.dart';

void main() {
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
    expect(find.text('Algebra'), findsWidgets);
    expect(find.text('9'), findsWidgets);
  });

  testWidgets('weekly matrix renders marks and lesson dots', (tester) async {
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

    expect(find.text('Algebra'), findsOneWidget);
    expect(find.text('9'), findsWidgets);
    expect(find.text('·'), findsWidgets);
  });

  testWidgets('weekly cell priority is mark then attendance then dot then empty', (tester) async {
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

    expect(find.text('8'), findsOneWidget);
    expect(find.text('Б'), findsOneWidget);
    expect(find.text('·'), findsWidgets);
  });

  testWidgets('term/year mode renders aggregates and opens SOR/SOCH drill-down', (tester) async {
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

    final subjectMath = find.byKey(const Key('grades-aggregate-subject-sub-math'));
    await tester.ensureVisible(subjectMath);
    await tester.tap(subjectMath);
    await tester.pumpAndSettle();

    expect(find.textContaining('12/15'), findsOneWidget);
    expect(find.textContaining('18/20'), findsOneWidget);
  });

  testWidgets('summative mood is primary over fraction fallback', (tester) async {
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

    expect(find.textContaining('7/10'), findsOneWidget);
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
