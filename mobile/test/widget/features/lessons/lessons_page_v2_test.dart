import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/features/lessons/application/lessons_controller.dart';
import 'package:kundi_mobile/features/lessons/domain/lessons_entity.dart';
import 'package:kundi_mobile/features/lessons/domain/lessons_repository.dart';
import 'package:kundi_mobile/features/lessons/presentation/lessons_page.dart';
import 'package:kundi_mobile/features/summary/application/summary_controller.dart';
import 'package:kundi_mobile/features/summary/domain/summary_entity.dart';
import 'package:kundi_mobile/features/summary/domain/summary_repository.dart';

void main() {
  testWidgets('lessons page renders current hero, tutor block and lessons list',
      (tester) async {
    final lessonsRepo = _FakeLessonsRepository(
      const <LessonsEntity>[
        LessonsEntity(
          id: 'l-1',
          date: '2026-04-05',
          lessonNumber: 2,
          subjectName: 'Algebra',
          topic: 'Quadratic equations',
          homeworkText: 'p.12 ex.3',
          requiresPhoto: false,
          gradeValue: '8',
          attendanceCode: 'N',
        ),
      ],
    );
    final summaryRepo = _FakeSummaryRepository(
      const SummaryEntity(
        available: true,
        lessonsCount: 300,
        homeworkCount: 210,
        resultsCount: 229,
        attendanceCount: 99,
        aggregatesCount: 35,
        recentResults: <SummaryResultHighlightEntity>[
          SummaryResultHighlightEntity(
            resultId: 'r-1',
            resultKind: 'regular',
            subjectName: 'Algebra',
            valueText: '8',
            recordedOn: '2026-04-05',
            resolvedMood: 'good',
          ),
        ],
        upcomingLessons: <SummaryLessonHighlightEntity>[
          SummaryLessonHighlightEntity(
            lessonId: 'u-1',
            lessonDate: '2026-04-06',
            lessonNumber: 1,
            subjectName: 'Biology',
            theme: 'Cells',
            homeworkText: 'Read page 45',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsRepositoryProvider.overrideWithValue(lessonsRepo),
          summaryRepositoryProvider.overrideWithValue(summaryRepo),
        ],
        child: const MaterialApp(home: LessonsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Algebra'), findsWidgets);
    expect(find.textContaining('Quadratic equations'), findsNothing);
    expect(find.textContaining('p.12 ex.3'), findsNothing);
    expect(find.textContaining('Центр дня'), findsOneWidget);
    expect(find.textContaining('Ближайшие уроки'), findsOneWidget);
    expect(find.textContaining('l-1'), findsNothing);
    expect(find.textContaining('Спросите Kundi'), findsOneWidget);
  });

  testWidgets('lessons page handles empty lessons with current empty state',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lessonsRepositoryProvider.overrideWithValue(
            _FakeLessonsRepository(const <LessonsEntity>[]),
          ),
          summaryRepositoryProvider.overrideWithValue(
            _FakeSummaryRepository(SummaryEntity.empty),
          ),
        ],
        child: const MaterialApp(home: LessonsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Центр дня'), findsOneWidget);
    expect(find.textContaining('Ближайшие уроки'), findsOneWidget);
    expect(find.textContaining('Уроки пока не загружены'), findsOneWidget);
  });
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
